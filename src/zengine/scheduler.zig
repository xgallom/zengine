//!
//! Scheduling system for the engine
//!

const std = @import("std");
const assert = std.debug.assert;
const AnyTaskList = std.DoublyLinkedList;

const log = std.log.scoped(.scheduler);

pub const PromiseError = error{NotReady};

pub fn Promise(comptime T: type) type {
    return struct {
        state: AtomicState,
        payload: T,

        pub const Self = @This();
        pub const NextTask = Task(T);

        pub const State = enum(u8) {
            waiting,
            resolved,
            read,
        };
        pub const AtomicState = std.atomic.Value(State);

        pub fn init() Self {
            return .{
                .state = .init(.waiting),
                .payload = undefined,
            };
        }

        pub fn tryGet(self: *Self) PromiseError!T {
            switch (self.state.load(.acquire)) {
                .waiting => return PromiseError.NotReady,
                .resolved => self.state.store(.read, .unordered),
                .read => {},
            }
            return self.payload;
        }

        pub fn get(self: *Self) T {
            while (true) : (std.atomic.spinLoopHint()) {
                return self.tryGet() catch continue;
            }
        }

        pub fn set(self: *Self, value: T) void {
            self.payload = value;
            self.state.store(.resolved, .release);
        }
    };
}

pub fn Task(comptime invokeFn: anytype) type {
    if (comptime @typeInfo(@TypeOf(invokeFn)) != .@"fn") @compileError("invoke must be a function");
    return struct {
        any: AnyTask,
        promise: Promise(RetVal),
        args: Args,

        pub const Self = @This();
        pub const Args = std.meta.ArgsTuple(@TypeOf(invokeFn));
        pub const RetVal = @typeInfo(@TypeOf(invokeFn)).@"fn".return_type orelse struct {};

        const vtable: AnyTask.VTable = .{
            .invoke = &invokeAny,
            .free = &freeAny,
        };

        pub fn init(self: *Self, args: Args) void {
            self.* = .{
                .any = .{
                    .vtable = vtable,
                },
                .promise = .init(),
                .args = args,
            };
        }

        fn invokeAny(any: *AnyTask) void {
            const self: *Self = @fieldParentPtr("any", any);
            self.promise.set(@call(.auto, invokeFn, self.args));
        }

        fn freeAny(any: *AnyTask, allocator: std.mem.Allocator) void {
            const self: *Self = @fieldParentPtr("any", any);
            allocator.destroy(self);
        }
    };
}

pub const AnyTask = struct {
    node: AnyTaskList.Node = .{},
    vtable: VTable,

    pub const VTable = struct {
        invoke: *const fn (any: *AnyTask) void,
        free: *const fn (any: *AnyTask, allocator: std.mem.Allocator) void,
    };

    pub inline fn invoke(self: *AnyTask) void {
        self.vtable.invoke(self);
    }

    pub inline fn free(self: *AnyTask, allocator: std.mem.Allocator) void {
        self.vtable.free(self, allocator);
    }
};

/// A managed list of tasks synchronized by a mutex
pub const TaskScheduler = struct {
    allocator: std.mem.Allocator,
    scheduled_tasks: AnyTaskList = .{},
    finished_tasks: AnyTaskList = .{},
    workers: Workers,
    mutex: std.Thread.Mutex = .{},
    begin: std.Thread.Condition = .{},
    end: std.Thread.Condition = .{},
    running: bool = false,

    const Self = @This();
    const Workers = std.ArrayList(Worker);

    pub fn init(allocator: std.mem.Allocator) !Self {
        const max_workers = (std.Thread.getCpuCount() catch 2) - 1;
        return .{
            .allocator = allocator,
            .workers = try .initCapacity(allocator, max_workers),
        };
    }

    pub fn deinit(self: *Self) void {
        self.join();
        self.cleanupTaskList(&self.scheduled_tasks);
        self.cleanupTaskList(&self.finished_tasks);
        self.workers.deinit(self.allocator);
    }

    /// Creates a new task immediately scheduling it for execution
    pub fn prepend(self: *Self, comptime invoke: anytype, args: std.meta.ArgsTuple(@TypeOf(invoke))) !*Task(invoke) {
        self.mutex.lock();
        defer self.mutex.unlock();

        const task = try self.allocator.create(Task(invoke));
        task.init(args);
        self.scheduled_tasks.prepend(&task.any.node);
        return task;
    }

    fn pop(self: *Self) ?*AnyTask {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.running) {
            log.debug("pop thread id {}", .{std.Thread.getCurrentId()});
            if (self.scheduled_tasks.pop()) |node| {
                self.finished_tasks.prepend(node);
                return @as(*AnyTask, @fieldParentPtr("node", node));
            } else {
                log.debug("end signal id {}", .{std.Thread.getCurrentId()});
                self.end.signal();
                self.begin.wait(&self.mutex);
                log.debug("wakeup signal id {}", .{std.Thread.getCurrentId()});
            }
        }

        return null;
    }

    pub fn run(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        assert(self.running == false);

        self.running = true;
        for (0..self.workers.capacity) |_| {
            const w = self.workers.addOneAssumeCapacity();
            try w.init(self);
        }
    }

    pub fn join(self: *Self) void {
        blk: {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (!self.running) break :blk;
            log.info("running = false", .{});
            self.running = false;
            self.begin.broadcast();
        }

        log.info("join workers", .{});
        for (self.workers.items) |*worker| worker.join();
        log.info("workers joined", .{});
        self.workers.clearRetainingCapacity();
    }

    /// Deallocates finished tasks
    pub fn cleanup(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.cleanupTaskList(self.finished_tasks);
    }

    fn cleanupTaskList(self: *Self, task_list: *AnyTaskList) void {
        while (task_list.pop()) |node| {
            const task: *AnyTask = @fieldParentPtr("node", node);
            task.free(self.allocator);
        }
    }

    const Worker = struct {
        self: *Self,
        done: bool = false,
        thread: std.Thread = undefined,

        fn init(w: *Worker, self: *Self) !void {
            w.* = .{ .self = self };
            w.thread = try std.Thread.spawn(.{ .allocator = self.allocator }, Worker.run, .{w});
        }

        fn join(w: *Worker) void {
            w.thread.join();
        }

        fn run(w: *Worker) void {
            while (w.self.pop()) |task| task.invoke();
        }
    };
};
