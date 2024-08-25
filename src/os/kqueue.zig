const std = @import("std");

const Allocator = std.mem.Allocator;

const KqueueHandlerFn = *const fn (poller: *KqueuePollerHandle, kevent: std.posix.Kevent, ctx: ?*anyopaque) void;

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

    pub fn removeHandler(self: *Self, kqueuePair: KqueuePair, data: isize, kqueueHandler: KqueueHandler) void {
        self.poller.addHandlerRaw(kqueuePair, data, kqueueHandler);
    }
};

pub const KqueuePoller = struct {
    const Self = @This();

    // 10ms (10 * 1000 nanos per micro * 1000 micros per milli)
    const ctrl_timeout = std.posix.timespec{ .sec = 0, .nsec = 10 * 1000 * 1000 };
    // 1ms (1 * 1000 nanos per micro * 1000 micros per milli)
    const timeout = std.posix.timespec{ .sec = 0, .nsec = 1 * 1000 * 1000 };

    allocator: Allocator,

    handlers_guard: std.Thread.RwLock,
    handlers: std.AutoHashMap(KqueuePair, KqueueHandler),

    kqfd: i32,

    polling_thread_guard: std.Thread.Mutex,
    polling_thread: ?std.Thread,

    shutdown_signal: std.atomic.Value(bool),

    pub fn init(allocator: Allocator) Self {
        const kqfd = std.posix.kqueue() catch unreachable;
        return Self{
            .allocator = allocator,
            .handlers_guard = .{},
            .handlers = std.AutoHashMap(KqueuePair, KqueueHandler).init(allocator),
            .kqfd = kqfd,
            .polling_thread_guard = .{},
            .polling_thread = null,
            .shutdown_signal = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *Self) void {
        self.join();
        self.handlers.deinit();
    }

    pub fn spawn(self: *Self) void {
        self.polling_thread_guard.lock();
        defer self.polling_thread_guard.unlock();

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
        self.polling_thread_guard.lock();
        defer self.polling_thread_guard.unlock();

        if (self.polling_thread) |polling_thread| {
            self.shutdown_signal.store(true, std.builtin.AtomicOrder.unordered);
            polling_thread.join();
            self.polling_thread = null;
            self.shutdown_signal.store(false, std.builtin.AtomicOrder.unordered);
        }
    }

    pub fn addHandler(self: *Self, kqueuePair: KqueuePair, data: isize, kqueueHandler: KqueueHandler) void {
        self.handlers_guard.lock();
        defer self.handlers_guard.unlock();
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
        const e = std.posix.kevent(self.kqfd, &[_]std.posix.Kevent{kevent}, &.{}, &ctrl_timeout) catch |err| {
            std.debug.panic("[KqueuePoller] error during kevent syscall adding handler: {any}", .{err});
        };
        if (e == -1) {
            std.debug.panic("[KqueuePoller] failed to register new event", .{});
        }

        self.handlers.put(kqueuePair, kqueueHandler) catch unreachable;
    }

    pub fn removeHandler(self: *Self, kqueuePair: KqueuePair) void {
        self.handlers_guard.lock();
        defer self.handlers_guard.unlock();
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

            const e = std.posix.kevent(self.kqfd, &[_]std.posix.Kevent{kevent}, &.{}, &ctrl_timeout) catch |err| {
                std.debug.panic("[KqueuePoller] error during kevent syscall removing handler: {any}", .{err});
            };
            if (e == -1) {
                std.debug.panic("[KqueuePoller] failed to delete new event", .{});
            }

            std.debug.assert(self.handlers.remove(kqueuePair));
        }
    }

    /// Blocks the current thread until the KqueuePoller is shut down via `signalShutdown`
    ///
    /// This is used internally as the entry point for `KqueuePoller.spawn`
    fn mainLoop(self: *Self) !void {
        const max_events = 1024;
        var events: [max_events]std.posix.Kevent = undefined;

        while (!self.shutdown_signal.load(std.builtin.AtomicOrder.unordered)) {
            const num_events = std.posix.kevent(self.kqfd, &.{}, &events, &timeout) catch |err| {
                std.debug.panic("[KqueuePoller] error during kevent syscall waiting on events: {any}", .{err});
            };

            // check err
            if (num_events == -1) {
                std.debug.panic("[KqueuePoller] failed to wait on kqueue", .{});
            } else if (num_events == 0) {
                // do nothing, we just timed out
            } else {
                for (0..num_events) |idx| {
                    const event = events[idx];
                    const pair = KqueuePair{
                        .ident = event.ident,
                        .filter = event.filter,
                    };

                    self.handlers_guard.lockShared();
                    defer self.handlers_guard.unlockShared();
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
    var poller = KqueuePoller.init(std.testing.allocator);
    defer poller.deinit();
}

test "expect to be able to spawn a KqueuePoller" {
    var poller = KqueuePoller.init(std.testing.allocator);
    defer poller.deinit();
    poller.spawn();
}

test "expect to be able to join a spawned KqueuePoller" {
    var poller = KqueuePoller.init(std.testing.allocator);
    poller.spawn();
    poller.join();
    defer poller.deinit();
}

test "expect to be able to add a Handler to a KqueuePoller" {
    var poller = KqueuePoller.init(std.testing.allocator);
    defer poller.deinit();

    const pair = KqueuePair{
        .ident = @intCast(1),
        .filter = std.posix.system.EVFILT.TIMER,
    };
    const handler = KqueueHandler.init(null, test_handler);

    poller.addHandler(pair, 1000, handler);
}

test "expect to be able to remove a Handler from a KqueuePoller" {
    var poller = KqueuePoller.init(std.testing.allocator);
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
    var poller = KqueuePoller.init(std.testing.allocator);
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
    var poller = KqueuePoller.init(std.testing.allocator);
    defer poller.deinit();

    const pair = KqueuePair{
        .ident = @intCast(1),
        .filter = std.posix.system.EVFILT.TIMER,
    };
    const handler = KqueueHandler.init(null, test_handler);

    poller.spawn();
    poller.addHandler(pair, 1000, handler);
}
