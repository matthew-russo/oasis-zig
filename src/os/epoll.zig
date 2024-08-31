const std = @import("std");

const Allocator = std.mem.Allocator;

const EpollerHandlerFn = *const fn (poller: *EpollerHandle, event: std.os.linux.epoll_event, ctx: ?*anyopaque) void;

pub const EpollHandler = struct {
    const Self = @This();

    ctx: ?*anyopaque,
    handler: EpollerHandlerFn,

    pub fn init(ctx: ?*anyopaque, handler: EpollerHandlerFn) Self {
        return Self{
            .ctx = ctx,
            .handler = handler,
        };
    }

    fn handle(self: *Self, poller: *EpollerHandle, event: std.os.linux.epoll_event) void {
        self.handler(poller, event, self.ctx);
    }
};

pub const EpollerHandle = struct {
    const Self = @This();

    poller: *Epoller,

    pub fn addHandler(self: *Self, fd: std.posix.socket_t, events: u32, epollHandler: EpollHandler) !void {
        try self.poller.addHandlerRaw(fd, events, epollHandler);
    }

    pub fn removeHandler(self: *Self, fd: std.posix.socket_t, events: u32, epollHandler: EpollHandler) !void {
        try self.poller.addHandlerRaw(fd, events, epollHandler);
    }
};

pub const Epoller = struct {
    const Self = @This();

    // 1ms (1 * 1000 nanos per micro * 1000 micros per milli)
    const timeout = std.posix.timespec{ .sec = 0, .nsec = 1 * 1000 * 1000 };

    allocator: Allocator,

    handlers_guard: std.Thread.RwLock,
    handlers: std.AutoHashMap(std.posix.socket_t, EpollHandler),

    epfd: std.posix.socket_t,

    polling_thread_guard: std.Thread.Mutex,
    polling_thread: ?std.Thread,

    shutdown_signal: std.atomic.Value(bool),

    pub fn init(allocator: Allocator) Self {
        const epfd = std.posix.epoll_create1(0) catch unreachable;
        return Self{
            .allocator = allocator,
            .handlers_guard = .{},
            .handlers = std.AutoHashMap(std.posix.socket_t, EpollHandler).init(allocator),
            .epfd = epfd,
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
            std.debug.panic("[Epoller] trying to spawn when already spawned", .{});
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

    pub fn addHandler(self: *Self, fd: std.posix.socket_t, events: u32, epollHandler: EpollHandler) !void {
        self.handlers_guard.lock();
        defer self.handlers_guard.unlock();
        try self.addHandlerRaw(fd, events, epollHandler);
    }

    fn addHandlerRaw(self: *Self, fd: std.posix.socket_t, events: u32, epollHandler: EpollHandler) !void {
        var evt: std.os.linux.epoll_event = undefined;
        evt.events = events;
        evt.data.fd = fd;
        try std.posix.epoll_ctl(self.epfd, std.os.linux.EPOLL.CTL_ADD, fd, &evt);
        try self.handlers.put(fd, epollHandler);
    }

    pub fn removeHandler(self: *Self, fd: std.posix.socket_t) !void {
        self.handlers_guard.lock();
        defer self.handlers_guard.unlock();
        try self.removeHandlerRaw(fd);
    }

    pub fn removeHandlerRaw(self: *Self, fd: std.posix.socket_t) !void {
        if (self.handlers.getPtr(fd)) |_| {
            try std.posix.epoll_ctl(self.epfd, std.os.linux.EPOLL.CTL_DEL, fd, null);
            std.debug.assert(self.handlers.remove(fd));
        }
    }

    /// Blocks the current thread until the Epoller is shut down via `join`
    ///
    /// This is used internally as the entry point for `Epoller.spawn`
    fn mainLoop(self: *Self) !void {
        const max_events = 1024;
        var events: [max_events]std.os.linux.epoll_event = undefined;

        while (!self.shutdown_signal.load(std.builtin.AtomicOrder.unordered)) {
            const num_events = std.posix.epoll_wait(self.epfd, &events, std.math.maxInt(i32));

            // check err
            if (num_events == -1) {
                std.debug.panic("[Server] failed to wait on epoll: {any}", .{std.os.linux.getErrno(num_events)});
            } else if (num_events == 0) {
                std.debug.panic("[Server] timeouts should be impossible if timeout is set to maxInt(i32)", .{});
            } else {
                for (0..num_events) |idx| {
                    const event = events[idx];

                    self.handlers_guard.lockShared();
                    defer self.handlers_guard.unlockShared();
                    const handler = self.handlers.getPtr(event.data.fd) orelse unreachable;
                    var self_handle = EpollerHandle{
                        .poller = self,
                    };
                    handler.handle(&self_handle, event);
                }
            }
        }
    }
};

fn test_handler(poller: *EpollerHandle, event: std.os.linux.epoll_event, ctx: ?*anyopaque) void {
    _ = poller;
    _ = event;
    _ = ctx;
}

test "expect to be able to construct and deconstruct a Epoller" {
    var poller = Epoller.init(std.testing.allocator);
    defer poller.deinit();
}

test "expect to be able to spawn a Epoller" {
    var poller = Epoller.init(std.testing.allocator);
    defer poller.deinit();
    poller.spawn();
}

test "expect to be able to join a spawned Epoller" {
    var poller = Epoller.init(std.testing.allocator);
    poller.spawn();
    poller.join();
    defer poller.deinit();
}

test "expect to be able to add a Handler to a Epoller" {
    var poller = Epoller.init(std.testing.allocator);
    defer poller.deinit();
    const handler = EpollHandler.init(null, test_handler);
    try poller.addHandler(@intCast(1), std.os.linux.EPOLL.IN, handler);
}

test "expect to be able to remove a Handler from a Epoller" {
    var poller = Epoller.init(std.testing.allocator);
    defer poller.deinit();
    const handler = EpollHandler.init(null, test_handler);
    try poller.addHandler(@intCast(1), std.os.linux.EPOLL.IN, handler);
    try poller.removeHandler(@intCast(1));
}

test "expect to be able to spawn a KqueuePoller with a Handler" {
    var poller = Epoller.init(std.testing.allocator);
    defer poller.deinit();
    const handler = EpollHandler.init(null, test_handler);
    try poller.addHandler(@intCast(1), std.os.linux.EPOLL.IN, handler);
    poller.spawn();
}

test "expect to be able to add a Handler after KqueuePoller has been spawned" {
    var poller = Epoller.init(std.testing.allocator);
    defer poller.deinit();
    const handler = EpollHandler.init(null, test_handler);
    poller.spawn();
    try poller.addHandler(@intCast(1), std.os.linux.EPOLL.IN, handler);
}
