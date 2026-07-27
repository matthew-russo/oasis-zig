const std = @import("std");

const Allocator = std.mem.Allocator;

// Zig 0.16 removed `std.posix.kqueue`/`std.posix.kevent`; call libc directly.
const c = std.c;

/// Slice-based wrapper mirroring the old `std.posix.kevent` signature, returning
/// the raw syscall result (>= 0 event count, or -1 on error).
fn keventSyscall(
    kq: i32,
    changelist: []const std.posix.Kevent,
    eventlist: []std.posix.Kevent,
    timeout: *const std.posix.timespec,
) c_int {
    return c.kevent(
        kq,
        changelist.ptr,
        @intCast(changelist.len),
        eventlist.ptr,
        @intCast(eventlist.len),
        timeout,
    );
}

const KqueueHandlerFn = *const fn (
    poller: *KqueuePollerHandle,
    kevent: std.posix.Kevent,
    ctx: ?*anyopaque,
) void;

pub const KqueueHandler = struct {
    const Self = @This();

    ctx: ?*anyopaque,
    handler: KqueueHandlerFn,

    pub fn init(ctx: ?*anyopaque, handler: KqueueHandlerFn) Self {
        return Self{
            .ctx = ctx,
            .handler = handler,
        };
    }

    fn handle(self: *Self, poller: *KqueuePollerHandle, kevent: std.posix.Kevent) void {
        self.handler(poller, kevent, self.ctx);
    }
};

pub const KqueuePair = struct {
    ident: usize,
    filter: i16,
};

pub const KqueuePollerHandle = struct {
    const Self = @This();

    poller: *KqueuePoller,

    pub fn addHandler(self: *Self, kqueuePair: KqueuePair, data: isize, kqueueHandler: KqueueHandler) void {
        self.poller.addHandlerRaw(kqueuePair, data, kqueueHandler);
    }

    pub fn removeHandler(self: *Self, kqueuePair: KqueuePair) void {
        self.poller.removeHandlerRaw(kqueuePair);
    }
};

pub const KqueuePoller = struct {
    const Self = @This();

    // 10ms (10 * 1000 nanos per micro * 1000 micros per milli)
    const ctrl_timeout = std.posix.timespec{ .sec = 0, .nsec = 10 * 1000 * 1000 };
    // 1ms (1 * 1000 nanos per micro * 1000 micros per milli)
    const timeout = std.posix.timespec{ .sec = 0, .nsec = 1 * 1000 * 1000 };

    allocator: Allocator,
    io: std.Io,

    handlers_guard: std.Io.RwLock,
    handlers: std.AutoHashMap(KqueuePair, KqueueHandler),

    kqfd: i32,

    polling_thread_guard: std.Io.Mutex,
    polling_thread: ?std.Thread,

    shutdown_signal: std.atomic.Value(bool),

    pub fn init(allocator: Allocator, io: std.Io) Self {
        const kqfd = c.kqueue();
        if (kqfd == -1) unreachable;
        return Self{
            .allocator = allocator,
            .io = io,
            .handlers_guard = .init,
            .handlers = std.AutoHashMap(KqueuePair, KqueueHandler).init(allocator),
            .kqfd = kqfd,
            .polling_thread_guard = .init,
            .polling_thread = null,
            .shutdown_signal = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *Self) void {
        self.join();
        self.handlers.deinit();
    }

    pub fn spawn(self: *Self) void {
        self.polling_thread_guard.lock(self.io) catch unreachable;
        defer self.polling_thread_guard.unlock(self.io);

        if (self.polling_thread) |_| {
            std.debug.panic("[KqueuePoller] trying to spawn when already spawned", .{});
        }

        self.polling_thread = std.Thread.spawn(.{}, Self.mainLoop, .{self}) catch unreachable;
    }

    pub fn isSpawned(self: *Self) bool {
        self.polling_thread_guard.lock();
        defer self.polling_thread_guard.unlock();

        if (self.polling_thread) |_| {
            return true;
        } else {
            return false;
        }
    }

    pub fn join(self: *Self) void {
        self.polling_thread_guard.lock(self.io) catch unreachable;
        defer self.polling_thread_guard.unlock(self.io);

        if (self.polling_thread) |polling_thread| {
            self.shutdown_signal.store(true, std.builtin.AtomicOrder.unordered);
            polling_thread.join();
            self.polling_thread = null;
            self.shutdown_signal.store(false, std.builtin.AtomicOrder.unordered);
        }
    }

    pub fn addHandler(self: *Self, kqueuePair: KqueuePair, data: isize, kqueueHandler: KqueueHandler) void {
        self.handlers_guard.lock(self.io) catch unreachable;
        defer self.handlers_guard.unlock(self.io);
        self.addHandlerRaw(kqueuePair, data, kqueueHandler);
    }

    fn addHandlerRaw(self: *Self, kqueuePair: KqueuePair, data: isize, kqueueHandler: KqueueHandler) void {
        const kevent: std.posix.Kevent = .{
            .ident = kqueuePair.ident,
            .filter = kqueuePair.filter,
            .flags = std.posix.system.EV.ADD | std.posix.system.EV.ENABLE,
            .fflags = 0,
            .data = data,
            .udata = 0,
        };
        const e = keventSyscall(self.kqfd, &[_]std.posix.Kevent{kevent}, &.{}, &ctrl_timeout);
        if (e == -1) {
            std.debug.panic("[KqueuePoller] failed to register new event", .{});
        }

        self.handlers.put(kqueuePair, kqueueHandler) catch unreachable;
    }

    pub fn removeHandler(self: *Self, kqueuePair: KqueuePair) void {
        self.handlers_guard.lock(self.io) catch unreachable;
        defer self.handlers_guard.unlock(self.io);
        self.removeHandlerRaw(kqueuePair);
    }

    pub fn removeHandlerRaw(self: *Self, kqueuePair: KqueuePair) void {
        if (self.handlers.getPtr(kqueuePair)) |_| {
            const kevent: std.posix.Kevent = .{
                .ident = kqueuePair.ident,
                .filter = kqueuePair.filter,
                .flags = std.posix.system.EV.DELETE,
                .fflags = 0,
                .data = 0,
                .udata = 0,
            };

            const e = keventSyscall(self.kqfd, &[_]std.posix.Kevent{kevent}, &.{}, &ctrl_timeout);
            if (e == -1) {
                std.debug.panic("[KqueuePoller] failed to delete new event", .{});
            }

            std.debug.assert(self.handlers.remove(kqueuePair));
        }
    }

    /// Blocks the current thread until the KqueuePoller is shut down via `join`
    ///
    /// This is used internally as the entry point for `KqueuePoller.spawn`
    fn mainLoop(self: *Self) !void {
        const max_events = 1024;
        var events: [max_events]std.posix.Kevent = undefined;

        while (!self.shutdown_signal.load(std.builtin.AtomicOrder.unordered)) {
            const num_events = keventSyscall(self.kqfd, &.{}, &events, &timeout);

            // check err
            if (num_events == -1) {
                std.debug.panic("[KqueuePoller] failed to wait on kqueue", .{});
            } else if (num_events == 0) {
                // do nothing, we just timed out
            } else {
                for (0..@intCast(num_events)) |idx| {
                    const event = events[idx];
                    const pair = KqueuePair{
                        .ident = event.ident,
                        .filter = event.filter,
                    };

                    self.handlers_guard.lockShared(self.io) catch unreachable;
                    defer self.handlers_guard.unlockShared(self.io);
                    const handler = self.handlers.getPtr(pair) orelse unreachable;
                    var self_handle = KqueuePollerHandle{
                        .poller = self,
                    };
                    handler.handle(&self_handle, event);
                }
            }
        }
    }
};

fn test_handler(poller: *KqueuePollerHandle, kevent: std.posix.Kevent, ctx: ?*anyopaque) void {
    _ = poller;
    _ = kevent;
    _ = ctx;
}

test "expect to be able to construct and deconstruct a KqueuePoller" {
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    var poller = KqueuePoller.init(std.testing.allocator, threaded.io());
    defer poller.deinit();
}

test "expect to be able to spawn a KqueuePoller" {
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    var poller = KqueuePoller.init(std.testing.allocator, threaded.io());
    defer poller.deinit();
    poller.spawn();
}

test "expect to be able to join a spawned KqueuePoller" {
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    var poller = KqueuePoller.init(std.testing.allocator, threaded.io());
    poller.spawn();
    poller.join();
    defer poller.deinit();
}

test "expect to be able to add a Handler to a KqueuePoller" {
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    var poller = KqueuePoller.init(std.testing.allocator, threaded.io());
    defer poller.deinit();

    const pair = KqueuePair{
        .ident = @intCast(1),
        .filter = std.posix.system.EVFILT.TIMER,
    };
    const handler = KqueueHandler.init(null, test_handler);

    poller.addHandler(pair, 1000, handler);
}

test "expect to be able to remove a Handler from a KqueuePoller" {
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    var poller = KqueuePoller.init(std.testing.allocator, threaded.io());
    defer poller.deinit();

    const pair = KqueuePair{
        .ident = @intCast(1),
        .filter = std.posix.system.EVFILT.TIMER,
    };
    const handler = KqueueHandler.init(null, test_handler);

    poller.addHandler(pair, 1000, handler);
    poller.removeHandler(pair);
}

test "expect to be able to spawn a KqueuePoller with a Handler" {
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    var poller = KqueuePoller.init(std.testing.allocator, threaded.io());
    defer poller.deinit();

    const pair = KqueuePair{
        .ident = @intCast(1),
        .filter = std.posix.system.EVFILT.TIMER,
    };
    const handler = KqueueHandler.init(null, test_handler);

    poller.addHandler(pair, 1000, handler);
    poller.spawn();
}

test "expect to be able to add a Handler after KqueuePoller has been spawned" {
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    var poller = KqueuePoller.init(std.testing.allocator, threaded.io());
    defer poller.deinit();

    const pair = KqueuePair{
        .ident = @intCast(1),
        .filter = std.posix.system.EVFILT.TIMER,
    };
    const handler = KqueueHandler.init(null, test_handler);

    poller.spawn();
    poller.addHandler(pair, 1000, handler);
}
