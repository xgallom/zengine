//!
//! Scheduling system for the engine
//!

const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.scheduler);

pub const PromiseError = error{NotReady};

pub fn Promise(comptime T: type) type {
    return struct {
        state: AtomicState,
        next_handler: AnyTaskHandler,
        payload: T,

        pub const Self = @This();
        pub const NextTask = Task(T);

        pub const State = enum(u8) {
            waiting,
            resolved,
            read,
        };
        pub const AtomicState = std.atomic.Value(State);

        pub fn init(scheduler: *TaskScheduler) Self {
            return .{
                .state = .init(.waiting),
                .next_handler = .init(scheduler),
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
            // self.next_handler.schedule();
        }
    };
}

pub fn Task(comptime invokeFn: anytype) type {
    return struct {
        node: AnyTaskListNode,
        promise: Promise(RetVal),
        args: Args,

        pub const Self = @This();
        pub const Args = std.meta.ArgsTuple(@TypeOf(invokeFn));
        pub const RetVal = @typeInfo(@TypeOf(invokeFn)).@"fn".return_type orelse struct {};

        const vtable: AnyTask.VTable = .{
            .invoke = &invokeAny,
            .free = &freeAny,
        };

        pub fn init(self: *Self, scheduler: *TaskScheduler, args: Args) void {
            self.* = .{
                .node = .{
                    .data = .{
                        .ptr = @ptrCast(self),
                        .vtable = vtable,
                    },
                },
                .promise = .init(scheduler),
                .args = args,
            };
        }

        pub fn after(self: *Self, other: *AnyTaskListNode) void {
            self.promise.next_handler.prepare(other);
        }

        fn invokeAny(ptr: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.promise.set(@call(.auto, invokeFn, self.args));
        }

        fn freeAny(ptr: *anyopaque, allocator: std.mem.Allocator) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            allocator.destroy(self);
        }
    };
}

pub const AnyTask = struct {
    ptr: *anyopaque,
    vtable: VTable,

    pub const VTable = struct {
        invoke: *const fn (ptr: *anyopaque) void,
        free: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
    };

    pub fn invoke(self: *AnyTask) void {
        self.vtable.invoke(self.ptr);
    }

    pub fn free(self: *AnyTask, allocator: std.mem.Allocator) void {
        self.vtable.free(self.ptr, allocator);
    }
};

const AnyTaskList = std.DoublyLinkedList(AnyTask);
const AnyTaskListNode = AnyTaskList.Node;

pub const AnyTaskHandler = struct {
    scheduler: *TaskScheduler,
    task_node: AtomicTaskListNode,

    const Self = @This();
    const AtomicTaskListNode = std.atomic.Value(?*AnyTaskListNode);

    pub fn init(scheduler: *TaskScheduler) Self {
        return .{
            .scheduler = scheduler,
            .task_node = .init(null),
        };
    }

    pub fn prepare(self: *Self, task_node: *AnyTaskListNode) void {
        self.task_node.store(task_node, .unordered);
    }

    // pub fn schedule(self: *Self) void {
    //     if (self.task_node.load(.acquire)) |task_node| self.scheduler.schedule(task_node);
    // }
};

/// A managed list of tasks synchronized by a mutex
pub const TaskScheduler = struct {
    allocator: std.mem.Allocator,
    // created_tasks: AnyTaskList = .{},
    scheduled_tasks: AnyTaskList = .{},
    finished_tasks: AnyTaskList = .{},
    workers: Workers,
    mutex: std.Thread.Mutex = .{},
    begin: std.Thread.Condition = .{},
    end: std.Thread.Condition = .{},
    running: bool = false,

    const Self = @This();
    const Workers = std.ArrayListUnmanaged(Worker);

    pub fn init(allocator: std.mem.Allocator) !Self {
        const max_workers = (std.Thread.getCpuCount() catch 2) - 1;
        return .{
            .allocator = allocator,
            .workers = try Workers.initCapacity(allocator, max_workers),
        };
    }

    pub fn deinit(self: *Self) void {
        // self.cleanupTaskList(&self.created_tasks);
        self.join();
        self.cleanupTaskList(&self.scheduled_tasks);
        self.cleanupTaskList(&self.finished_tasks);
        self.workers.deinit(self.allocator);
    }

    // /// Creates a new task
    // pub fn prepare(self: *Self, comptime invoke: anytype, args: std.meta.ArgsTuple(@TypeOf(invoke))) !*Task(invoke) {
    //     self.mutex.lock();
    //     defer self.mutex.unlock();
    //
    //     const task = try self.allocator.create(Task(invoke));
    //     task.init(self, args);
    //     self.created_tasks.prepend(&task.node);
    //     return task;
    // }
    //
    // fn scheduleImpl(self: *Self, node: *AnyTaskListNode) void {
    //     self.created_tasks.remove(node);
    //     self.scheduled_tasks.prepend(node);
    // }
    //
    // /// Schedules a task created with `prepare` for execution
    // pub fn schedule(self: *Self, node: *AnyTaskListNode) void {
    //     self.mutex.lock();
    //     defer self.mutex.unlock();
    //
    //     self.scheduleImpl(node);
    // }

    /// Creates a new task immediately scheduling it for execution
    pub fn prepend(self: *Self, comptime invoke: anytype, args: std.meta.ArgsTuple(@TypeOf(invoke))) !*Task(invoke) {
        self.mutex.lock();
        defer self.mutex.unlock();

        const task = try self.allocator.create(Task(invoke));
        task.init(self, args);
        self.scheduled_tasks.prepend(&task.node);
        return task;
    }

    // pub fn worker(self: *Self) !*Worker {
    //     const worker = try self.allocator.create(Worker);
    //     worker.init(self);
    //     try worker.spawn();
    // }

    fn pop(self: *Self) ?*AnyTask {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.running) {
            log.debug("pop thread id {}", .{std.Thread.getCurrentId()});
            if (self.scheduled_tasks.pop()) |task| {
                self.finished_tasks.prepend(task);
                return &task.data;
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
        while (task_list.pop()) |task| task.data.free(self.allocator);
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
