//!
//! The zengine performance measuring module
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("allocators.zig");
const global = @import("global.zig");
const KeyTree = @import("key_tree.zig").KeyTree;
const math = @import("math.zig");
const RadixTree = @import("radix_tree.zig").RadixTree;
const time = @import("time.zig");

const log = std.log.scoped(.perf);
pub const perf_sections = sections(@This(), &.{ .log, .update_avg });

const framerate_buf_count = 1 << 8;
const framerate_idx_mask: usize = framerate_buf_count - 1;

const frametime_buf_count = 1 << 8;
const frametime_idx_mask: usize = frametime_buf_count - 1;
const frametime_over_bit: usize = 1 << 9;

pub const SectionsTree = KeyTree(struct { key: []const u8, value: *Section }, .{ .insertion_order = .insert_last });

const Self = struct {
    framerate_buf: []u64,
    framerate_idx: usize = 0,
    framerate: u32 = 1,
    sections: SectionHashMap,
    tree: SectionsTree,

    const SectionHashMap = std.StringArrayHashMapUnmanaged(*Section);

    fn init(self: *Self) !void {
        const gpa = allocators.gpa();
        const framerate_buf = try gpa.alloc(u64, framerate_buf_count);
        @memset(framerate_buf, 0);

        self.* = .{
            .framerate_buf = framerate_buf,
            .sections = try .init(gpa, &.{}, &.{}),
            .tree = try .init(gpa, 128),
        };
    }

    fn deinit(self: *Self) void {
        const gpa = allocators.gpa();
        gpa.free(self.framerate_buf);
        var iter = self.sections.iterator();
        while (iter.next()) |i| gpa.destroy(i.value_ptr.*);
        self.sections.deinit(gpa);
        self.tree.deinit();
    }

    fn update(self: *Self, now: u64) void {
        const framerate_start_time = (now -| 1001) + 1;
        self.framerate = 1;
        for (self.framerate_buf) |item| {
            if (item >= framerate_start_time) self.framerate += 1;
        }
        self.framerate_idx = (self.framerate_idx + 1) & framerate_idx_mask;
        self.framerate_buf[self.framerate_idx] = now;
    }
};

const Section = struct {
    clock: time.Clock = .{},
    pause_clock: time.Clock = .{},
    avg: u64 = 0,
    idx: usize = 0,
    buf: [frametime_buf_count]u64 = @splat(0),

    pub fn begin(self: *Section) void {
        self.clock.start(time.getNano());
        self.pause_clock.reset();
    }

    pub fn beginPaused(self: *Section) void {
        const now = time.getNano();
        self.clock.start(now);
        self.clock.pause(&self.pause_clock, now);
    }

    pub fn end(self: *Section) void {
        const now = time.getNano();
        if (self.pause_clock.isRunning()) self.clock.unpause(&self.pause_clock, now);
        self.buf[self.idx & frametime_idx_mask] = self.clock.elapsed(now);
        self.clock.reset();
        self.inc();
    }

    pub fn pause(self: *Section) void {
        self.clock.pause(&self.pause_clock, time.getNano());
    }

    pub fn unpause(self: *Section) void {
        self.clock.unpause(&self.pause_clock, time.getNano());
    }

    fn inc(self: *Section) void {
        var next_idx = (self.idx + 1) & frametime_idx_mask;
        next_idx |= self.idx & ~frametime_idx_mask;
        if (next_idx == 0) next_idx |= frametime_over_bit;
        self.idx = next_idx;
    }

    fn avgTime(self: *const Section) time.Time {
        return .{ .ns = self.avg };
    }

    fn computeAvg(self: *Section) u64 {
        var acc: u64 = 0;
        const end_idx = @min(self.idx, frametime_buf_count);
        if (end_idx == 0) return 0;
        for (0..end_idx) |n| acc += self.buf[n];
        return acc / end_idx;
    }
};

var is_init = false;
var is_constructed = false;
var global_state: Self = undefined;

pub fn init() !void {
    assert(!is_init);
    try global_state.init();
    is_init = true;

    try perf_sections.register();
}

pub fn commitGraph() !void {
    assert(is_init);
    assert(!is_constructed);

    global_state.sections.lockPointers();
    var iter = global_state.sections.iterator();
    while (iter.next()) |i| try global_state.tree.insert(
        i.key_ptr.*,
        .{ .key = i.key_ptr.*, .value = i.value_ptr.* },
    );
    is_constructed = true;
}

pub fn releaseGraph() void {
    assert(is_init);
    assert(is_constructed);
    global_state.sections.unlockPointers();
    is_constructed = false;
}

pub fn deinit() void {
    assert(is_init);
    global_state.deinit();
    is_init = false;
}

pub fn update(now: u64) void {
    assert(is_init);
    global_state.update(now);
}

pub fn updateAvg() void {
    assert(is_init);
    assert(is_constructed);

    perf_sections.sub(.update_avg).begin();
    var iter = global_state.sections.iterator();
    while (iter.next()) |i| i.value_ptr.*.avg = i.value_ptr.*.computeAvg();
    perf_sections.sub(.update_avg).end();
}

pub fn logPerf() void {
    assert(is_init);
    assert(is_constructed);

    log.info("framerate: {}", .{framerate()});

    const IterTree = struct {
        fn iterTree(node: *const SectionsTree.Node, label: []const u8, offset: usize) !void {
            if (node.value) |index| {
                const avg = index.value.avg;
                log.info("{s}[{s}] {D}", .{
                    global.spaces(offset),
                    label,
                    avg,
                });
            } else {
                log.info("{s}[{s}]", .{ global.spaces(offset), label });
            }

            var edge_node = node.edges.first;
            while (edge_node != null) : (edge_node = edge_node.?.next) {
                const edge: *const SectionsTree.Edge = @fieldParentPtr("edge_node", edge_node.?);
                try iterTree(&edge.target, edge.label, offset + 4);
            }
        }
    };

    try IterTree.iterTree(global_state.tree.root, "", 0);

    log.info("render / frame: {d:.2}%", .{
        math.percent(
            getAvg("gfx.Renderer.draw").toFloat().asValue() /
                getAvg("main.frame").toFloat().asValue(),
        ),
    });
}

pub inline fn framerate() u32 {
    assert(is_init);
    return global_state.framerate;
}

pub inline fn getAvg(label: []const u8) time.Time {
    assert(is_init);
    assert(is_constructed);
    if (global_state.sections.get(label)) |value| return value.avgTime();
    unreachable;
}

pub inline fn sectionsTree() *const SectionsTree {
    return &global_state.tree;
}

pub fn sections(comptime this: type, comptime labels: []const @TypeOf(.enum_literal)) type {
    var label_names: []const []const u8 = &[_][]const u8{};
    inline for (labels) |label| label_names = label_names ++ [_][]const u8{@tagName(label)};
    return TaggedSections(@typeName(this), label_names);
}

pub fn TaggedSections(comptime this: []const u8, comptime labels: []const []const u8) type {
    const root = TaggedSection(this);

    var struct_fields: []const std.builtin.Type.StructField = &[_]std.builtin.Type.StructField{};
    var enum_fields: []const std.builtin.Type.EnumField = &[_]std.builtin.Type.EnumField{};
    var idx = 0;
    inline for (labels) |label| {
        const SectionType = root.subTag(label);
        struct_fields = struct_fields ++ [_]std.builtin.Type.StructField{.{
            .name = label[0.. :0],
            .type = type,
            .default_value_ptr = &SectionType,
            .is_comptime = true,
            .alignment = @alignOf(SectionType),
        }};
        enum_fields = enum_fields ++ [_]std.builtin.Type.EnumField{.{
            .name = label[0.. :0],
            .value = idx,
        }};
        idx += 1;
    }

    const Sections = @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = struct_fields,
        .decls = &[_]std.builtin.Type.Declaration{},
        .is_tuple = false,
    } });

    const LabelEnum = @Type(.{ .@"enum" = .{
        .tag_type = if (labels.len > 0) std.math.IntFittingRange(0, labels.len - 1) else u0,
        .fields = enum_fields,
        .decls = &[_]std.builtin.Type.Declaration{},
        .is_exhaustive = true,
    } });

    return struct {
        pub const tag = this;
        pub const items = Sections{};
        pub const Label = LabelEnum;

        pub fn register() !void {
            inline for (labels) |label| try root.subTag(label).register();
        }

        pub fn sub(comptime label: Label) type {
            return root.subTag(@tagName(label));
        }

        pub fn avgs() std.EnumArray(Label, time.Time) {
            var result: std.EnumArray(Label, time.Time) = undefined;
            inline for (labels, 0..) |label, n| result.set(@enumFromInt(n), root.subTag(label).avg());
            return result;
        }
    };
}

pub fn section(comptime this: type) type {
    return TaggedSection(@typeName(this));
}

pub fn TaggedSection(comptime _tag: []const u8) type {
    return struct {
        pub const tag = _tag;

        pub fn register() !void {
            assert(is_init);
            assert(!is_constructed);
            const value = try allocators.gpa().create(Section);
            errdefer allocators.gpa().destroy(value);
            value.* = .{};
            try global_state.sections.putNoClobber(allocators.gpa(), tag, value);
        }

        pub fn sub(comptime sub_label: @TypeOf(.enum_literal)) type {
            return TaggedSection(tag ++ "." ++ @tagName(sub_label));
        }

        fn subTag(comptime sub_tag: []const u8) type {
            return TaggedSection(tag ++ "." ++ sub_tag);
        }

        pub fn sections(comptime sub_labels: []const @TypeOf(.enum_literal)) type {
            var label_names: []const []const u8 = &[_][]const u8{};
            inline for (sub_labels) |sub_label| label_names = label_names ++ [_][]const u8{@tagName(sub_label)};
            return TaggedSections(tag, label_names);
        }

        pub fn begin() void {
            getPtr().begin();
        }

        pub fn beginPaused() void {
            getPtr().beginPaused();
        }

        pub fn end() void {
            getPtr().end();
        }

        pub fn pause() void {
            getPtr().pause();
        }

        pub fn unpause() void {
            getPtr().unpause();
        }

        pub fn avg() time.Time {
            assert(is_constructed);
            return .{ .ns = getPtr().avg };
        }

        pub fn getPtr() *Section {
            assert(is_init);
            const self = global_state.sections.get(tag);
            assert(self != null);
            return self.?;
        }
    };
}
