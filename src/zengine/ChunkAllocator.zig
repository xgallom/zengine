//!
//! The zengine chunk allocator implementation
//!
//! Can address up to 512GB
//!

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

const c = @import("ext.zig").c;

const log = std.log.scoped(.chunk_allocator);

child_allocator: Allocator,
state: State,

const Self = @This();

pub const State = struct {
    chunks: std.ArrayList(Chunk) = .empty,

    pub fn promote(state: State, child_allocator: Allocator) Self {
        return .{ .child_allocator = child_allocator, .state = state };
    }
};

pub const Id = enum(u64) {
    invalid,
    _,

    pub const Meta = enum(u1) { invalid, valid };
    pub const Gen = u31;
    pub const Idx = u32;
    pub const Decomposed = packed struct(u64) {
        meta: Meta,
        gen: Gen,
        idx: Idx,

        pub fn init(g: Gen, i: Idx) Decomposed {
            return .{ .meta = .valid, .gen = g, .idx = i };
        }
    };

    pub inline fn compose(id: Decomposed) Id {
        return @enumFromInt(@as(u64, @bitCast(id)));
    }

    pub inline fn decompose(id: Id) Decomposed {
        return @bitCast(@intFromEnum(id));
    }

    pub inline fn isValid(id: Id) bool {
        return id != .invalid;
    }

    pub inline fn gen(id: Id) Idx {
        return id.decompose().gen;
    }

    pub inline fn idx(id: Id) Idx {
        return id.decompose().idx;
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const d = self.decompose();
        switch (d.meta) {
            .invalid => _ = try writer.write("invalid"),
            .valid => try writer.print("{}@{}", .{ d.idx, d.gen }),
        }
    }
};

pub const Chunk = struct {
    ptr: ?*[chunk_len]u8 = null,

    /// 64 KB
    pub const chunk_len = 1 << 16;
    pub const chunk_alignment = std.mem.Alignment.fromByteUnits(chunk_len);
    pub const chunk_mask = chunk_len - 1;

    pub const Slice = struct {
        ptr: [][chunk_len]u8 = &.{},

        pub fn create(gpa: Allocator, count: usize) !@This() {
            return .{ .ptr = try gpa.alignedAlloc([chunk_len]u8, chunk_alignment, count) };
        }

        pub fn deinit(self: *Slice, gpa: Allocator) void {
            if (self.isValid()) self.destroy(gpa);
        }

        pub fn destroy(self: *Slice, gpa: Allocator) void {
            gpa.free(self.ptr);
        }

        pub fn slice(self: Slice, comptime T: type) []T {
            return @ptrCast(self.ptr);
        }

        pub fn isValid(self: Slice) bool {
            return self.ptr.len != 0;
        }
    };

    pub fn create(gpa: Allocator) !Chunk {
        return .{ .ptr = try gpa.alignedAlloc(u8, chunk_alignment, chunk_len) };
    }

    pub fn alloc(gpa: Allocator, count: usize, comptime alignment: ?Alignment) !Slice(alignment) {
        return .create(gpa, alignment, count);
    }

    pub fn deinit(self: *Chunk, gpa: Allocator) void {
        if (self.isValid()) self.destroy(gpa);
    }

    pub fn destroy(self: *Chunk, gpa: Allocator) void {
        assert(self.isValid());
        gpa.free(self.ptr.?);
        self.ptr = null;
    }

    pub fn slice(self: Chunk, comptime T: type) []T {
        assert(self.isValid());
        return @ptrCast(self.ptr.?);
    }

    pub fn fromOwned(ptr: *[chunk_len]u8) Chunk {
        return .{ .ptr = if (ptr.len != 0) ptr else null };
    }

    pub fn toOwned(self: *Chunk) *[chunk_len]u8 {
        assert(self.isValid());
        defer self.ptr = null;
        return self.ptr.?;
    }

    pub fn isValid(self: Chunk) bool {
        return self.ptr != null;
    }
};

pub const ChunkSliceMap = struct {
    slice: []Chunk,
};

const vtable = Allocator.VTable{
    .alloc = alloc,
    .resize = resize,
    .remap = Allocator.noRemap,
    .free = free,
};

pub fn init(child_allocator: Allocator) Self {
    return (State{}).promote(child_allocator);
}

pub fn deinit(self: *Self) void {
    for (self.state.chunks.items) |*chunk| chunk.deinit(self.child_allocator);
    if (self.state.chunks.capacity > 0) {
        var chunk = Chunk.fromOwned(@ptrCast(self.state.chunks.items.ptr));
        chunk.destroy(self.child_allocator);
    }
}

pub fn create(self: *Self) !Chunk {
    if (self.state.chunks.capacity == 0) {
        const chunks = try Chunk.create(self.child_allocator);
        self.state.chunks = .initBuffer(chunks.slice(Chunk));
    }
    if (self.state.chunks.unusedCapacitySlice().len == 0) return Allocator.Error.OutOfMemory;
    const chunk = try Chunk.create(self.child_allocator);
    self.state.chunks.appendAssumeCapacity(chunk);
    return chunk;
}

pub fn destroy(self: *Self, chunk: Chunk) void {
    const n: usize = for (self.state.chunks.items, 0..) |item, n| {
        if (item.ptr == chunk.ptr) break n;
    } else {
        log.err("chunk not found: {*}", .{chunk});
        unreachable;
    };
    self.state.chunks.orderedRemove(n);
    chunk.destroy(self.child_allocator);
}

fn alloc(self: *Self, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
    _ = ret_addr;
    if (alignment.compare(.gt, Chunk.alignment)) return null;
    const chunk = self.create() catch return null;
    return chunk.ptr[0..len];
}

pub fn resize(self: *Self, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
    _ = self;
    _ = memory;
    _ = ret_addr;
    return alignment.compare(.lte, Chunk.alignment) and new_len <= Chunk.len;
}

pub fn free(self: *Self, memory: []u8, alignment: Alignment, ret_addr: usize) void {
    _ = alignment;
    _ = ret_addr;
    self.destroy(.fromOwned(@ptrCast(memory.ptr)));
}

pub fn allocator(self: *Self) Allocator {
    return .{
        .ptr = @ptrCast(self),
        .vtable = &vtable,
    };
}
