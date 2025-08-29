//!
//! Scheduling system for the engine
//!

const std = @import("std");
const assert = std.debug.assert;

const ProcessExit = enum {
    unlock,
    lock,
};

pub const PromiseError = error{NotReady};

/// A promise type
pub fn Promise(comptime T: type) type {
    return struct {
        state: AtomicState,
        next_handler: TaskHandler,
        payload: T,

        pub const Self = @This();
        pub const NextTask = Task(T);

        pub const State = enum(u8) {
            waiting,
            resolved,
            read,
        };
        pub const AtomicState = std.atomic.Value(State);

        pub fn init(al: *TaskArrayList) Self {
            return .{
                .state = .init(.waiting),
                .next_handler = .init(al),
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
            self.next_handler.schedule();
        }
    };
}

pub fn Task(comptime invokeFn: anytype) type {
    return struct {
        node: TaskList.Node,
        promise: Promise(RetVal),
        args: Args,

        pub const Self = @This();
        pub const Args = std.meta.ArgsTuple(@TypeOf(invokeFn));
        pub const RetVal = @typeInfo(@TypeOf(invokeFn)).@"fn".return_type orelse struct {};

        const vtable: AnyTask.VTable = .{
            .invoke = &invokeAny,
            .free = &freeAny,
        };

        pub fn init(self: *Self, al: *TaskArrayList, args: Args) void {
            self.* = .{
                .node = .{
                    .data = .{
                        .ptr = @ptrCast(self),
                        .vtable = &vtable,
                    },
                },
                .promise = .init(al),
                .args = args,
            };
        }

        pub fn after(self: *Self, other: *TaskList.Node) void {
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
    vtable: *const VTable,

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

const TaskList = std.DoublyLinkedList(AnyTask);

pub const TaskHandler = struct {
    al: *TaskArrayList,
    task_node: AtomicTaskListNode,

    const Self = @This();
    const AtomicTaskListNode = std.atomic.Value(?*TaskList.Node);

    pub fn init(al: *TaskArrayList) Self {
        return .{
            .al = al,
            .task_node = .init(null),
        };
    }

    pub fn prepare(self: *Self, task_node: *TaskList.Node) void {
        self.task_node.store(task_node, .unordered);
    }

    pub fn schedule(self: *Self) void {
        if (self.task_node.load(.acquire)) |task_node| self.al.schedule(task_node);
    }
};

pub const TaskArrayList = struct {
    allocator: std.mem.Allocator,
    scheduled_tasks: TaskList = .{},
    tasks: TaskList = .{},
    free_tasks: TaskList = .{},
    mutex: std.Thread.Mutex = .{},

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.cleanupTaskList(&self.scheduled_tasks);
        self.cleanupTaskList(&self.tasks);
        self.cleanupTaskList(&self.free_tasks);
    }

    /// Creates a new task
    pub fn prepare(self: *Self, comptime invoke: anytype, args: std.meta.ArgsTuple(@TypeOf(invoke))) !*Task(invoke) {
        self.mutex.lock();
        defer self.mutex.unlock();

        const task = try self.allocator.create(Task(invoke));
        task.init(self, args);
        self.scheduled_tasks.prepend(&task.node);
        return task;
    }

    fn scheduleImpl(self: *Self, node: *TaskList.Node) void {
        self.scheduled_tasks.remove(node);
        self.tasks.prepend(node);
    }

    /// Schedules a task created with `prepare` for execution
    pub fn schedule(self: *Self, node: *TaskList.Node) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.scheduleImpl(node);
    }

    /// Creates a new task scheduling it for execution
    pub fn append(self: *Self, comptime invoke: anytype, args: std.meta.ArgsTuple(@TypeOf(invoke))) !*Task(invoke) {
        self.mutex.lock();
        defer self.mutex.unlock();

        const task = try self.allocator.create(Task(invoke));
        task.init(self, args);
        self.tasks.prepend(&task.node);
        return task;
    }

    /// Assumes locked mutex
    fn processFirstImpl(self: *Self, comptime process_exit: ProcessExit) bool {
        if (self.tasks.pop()) |task| {
            self.free_tasks.prepend(task);
            self.mutex.unlock();
            task.data.invoke();
            if (process_exit == .lock) self.mutex.lock();
            return true;
        }
        if (process_exit == .unlock) self.mutex.unlock();
        return false;
    }

    /// Takes the first task from the list and executes it
    pub fn processFirst(self: *Self) bool {
        self.mutex.lock();
        return self.processFirstImpl(.unlock);
    }

    /// Takes all the tasks from the list and executes them
    pub fn processAll(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.processFirstImpl(.lock)) {}
    }

    /// Deallocates finished tasks
    pub fn cleanup(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.cleanupTaskList(self.free_tasks);
    }

    fn cleanupTaskList(self: *Self, task_list: *TaskList) void {
        while (task_list.pop()) |task| task.data.free(self.allocator);
    }
};
