//!
//! The zengine performance measuring module
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("allocators.zig");
const global = @import("global.zig");
const containers = @import("containers.zig");
const math = @import("math.zig");
const SwapWrapper = @import("containers.zig").SwapWrapper;
const time = @import("time.zig");

const log = std.log.scoped(.perf);
pub const perf_sections = sections(@This(), &.{.updateStats});
pub const empty_section = TaggedSection("perf", "empty", "perf", .sub);

const framerate_buf_count = 1 << 8;
const framerate_mask = math.IntMask(framerate_buf_count);

const frame_stats_count = 1 << 8;
const stats_update_interval = 200;

const frametime_buf_count = 1 << 8;
const frametime_mask = math.IntMask(frametime_buf_count);

const stack_trace_count = 16;

pub const Value = *Section;
pub const KeyIndex = struct {
    key: []const u8,
    value: Value,
};
pub const SectionsTree = containers.KeyTree(KeyIndex, .{
    .has_depth = true,
});
pub const SectionsListTree = containers.Tree(KeyIndex, .{
    .pool_options = .{ .growable = false },
    .insertion_order = .insert_last,
    .has_depth = true,
});
pub const SectionsList = SwapWrapper(SectionsListTree, .{});

const SectionType = enum(u2) { root, call, sub };
const SectionState = enum(u2) { began, began_paused, ended };

const Self = struct {
    active_list: SectionsListTree,
    tree: SectionsTree,
    list: SectionsList,
    framerate_buf: []u64,
    framerate_idx: usize = 0,
    last_update_idx: usize = 0,
    frames_per_sample: u32 = 0,
    framerates_avg: []u32,
    framerates_max: []u32,
    framerates_min: []u32,
    update_stats_times: []u32,
    sections: SectionHashMap,
    list_pusher: SectionsListTree.Pusher = undefined,
    update_stats_timer: time.StaticTimer(stats_update_interval),
    framerate_imm_clock: time.Clock,
    framerate: u16 = 1,
    framerate_max: u16 = 0,
    framerate_min: u16 = 0,

    const SectionHashMap = std.StringArrayHashMapUnmanaged(*Section);

    fn init(self: *Self) !void {
        const gpa = allocators.arena(.perf);
        const framerate_buf = try gpa.alloc(u64, framerate_buf_count);
        @memset(framerate_buf, 0);

        const framerates_avg = try gpa.alloc(u32, frame_stats_count);
        @memset(framerates_avg, 0);
        const framerates_min = try gpa.alloc(u32, frame_stats_count);
        @memset(framerates_min, 0);
        const framerates_max = try gpa.alloc(u32, frame_stats_count);
        @memset(framerates_max, 0);

        const update_stats_times = try gpa.alloc(u32, frame_stats_count);
        for (update_stats_times, 0..) |*stat_time, n| {
            stat_time.* = @intCast(n * stats_update_interval);
        }

        const initListItem = struct {
            fn initListItem() !SectionsListTree {
                return .init(allocators.arena(.perf), 128);
            }
        }.initListItem;

        self.* = .{
            .active_list = try initListItem(),
            .tree = try .init(gpa, 128),
            .list = try .initCall(initListItem),
            .framerate_buf = framerate_buf,
            .framerates_avg = framerates_avg,
            .framerates_min = framerates_min,
            .framerates_max = framerates_max,
            .update_stats_times = update_stats_times,
            .sections = try .init(gpa, &.{}, &.{}),
            .update_stats_timer = .init,
            .framerate_imm_clock = .init(time.getNano()),
        };
        self.list_pusher = self.list.getPtr().pusher();
    }

    fn deinit(self: *Self) void {
        const gpa = allocators.arena(.perf);
        gpa.free(self.framerate_buf);
        gpa.free(self.framerates_avg);
        gpa.free(self.framerates_min);
        gpa.free(self.framerates_max);
        gpa.free(self.update_stats_times);
        var iter = self.sections.iterator();
        while (iter.next()) |i| gpa.destroy(i.value_ptr.*);
        self.sections.deinit(gpa);
        self.tree.deinit();
        self.list.deinit(.{});
    }

    fn reset(self: *Self) void {
        const list = self.list.advance();
        list.clearRetainingCapacity();
        self.list_pusher = list.pusher();
    }

    fn update(self: *Self, now: u64) void {
        if (self.framerate_min == 0) {
            @branchHint(.cold);
            self.framerate_min = std.math.maxInt(u16);
        }

        const framerate_start_time = (now -| 1001) + 1;
        self.framerate = 1;
        for (self.framerate_buf) |item| {
            if (item >= framerate_start_time) self.framerate += 1;
        }

        self.framerate_idx += 1;
        const idx = framerate_mask.offset(self.framerate_idx);
        self.framerate_buf[idx] = now;

        const now_nano = time.getNano();
        const framerate_imm: u16 = @intCast(
            @max(1, time.Unit.makePer(.ns, .s) / self.framerate_imm_clock.elapsed(now_nano)),
        );
        self.framerate_min = @min(self.framerate_min, framerate_imm);
        self.framerate_max = @max(self.framerate_max, framerate_imm);
        self.framerate_imm_clock.start(now_nano);
    }

    fn updateStats(self: *Self, now: u64, comptime force_update: bool) void {
        if (!force_update) {
            if (!self.update_stats_timer.updated(now)) return;
        } else {
            @branchHint(.cold);
            self.update_stats_timer.set(now);
        }

        perf_sections.sub(.updateStats).begin();

        @memmove(self.framerates_avg[0 .. frame_stats_count - 1], self.framerates_avg[1..]);
        self.framerates_avg[frame_stats_count - 1] = self.framerate;

        @memmove(self.framerates_min[0 .. frame_stats_count - 1], self.framerates_min[1..]);
        self.framerates_min[frame_stats_count - 1] = self.framerate_min;
        @memmove(self.framerates_max[0 .. frame_stats_count - 1], self.framerates_max[1..]);
        self.framerates_max[frame_stats_count - 1] = self.framerate_max;

        self.framerate_min = 0;
        self.framerate_max = 0;

        self.commitList() catch unreachable;

        var iter = self.sections.iterator();
        while (iter.next()) |i| i.value_ptr.*.updateStats();

        self.frames_per_sample = @intCast(self.framerate_idx - self.last_update_idx);
        self.last_update_idx = self.framerate_idx;

        perf_sections.sub(.updateStats).end();
    }

    fn commitList(self: *Self) !void {
        var walk = self.list.getPrevPtr().edges.first;
        self.active_list.clearRetainingCapacity();
        var pusher = self.active_list.pusher();

        if (walk == null) return;
        loop: while (true) {
            const node: *SectionsListTree.Node = @fieldParentPtr("edge_node", walk.?);
            _ = try pusher.push(node.value);
            if (node.edges.first) |first| {
                walk = first;
                continue;
            }

            _ = pusher.pop();
            if (node.edge_node.next) |next| {
                walk = next;
                continue;
            }

            if (node.parent != null) {
                var back_walk = node.parent.?;
                while (true) {
                    _ = pusher.pop();
                    if (back_walk.edge_node.next) |next| {
                        walk = next;
                        continue :loop;
                    }
                    if (back_walk.parent) |parent| {
                        back_walk = parent;
                        continue;
                    }
                    break;
                }
            }

            return;
        }
    }

    fn beginSection(self: *Self, comptime tag: []const u8, ptr: *Section, ret_addr: usize) !void {
        if (ptr.first_address[0] != ret_addr) {
            ptr.first_address[0] = ret_addr;
            ptr.stack_trace[0].instruction_addresses = &ptr.stack_trace_buf[0];
            ptr.stack_trace[0].index = 0;
            std.debug.captureStackTrace(ret_addr, &ptr.stack_trace[0]);
        }
        _ = try self.list_pusher.push(.{ .key = tag, .value = ptr });
    }

    fn endSection(self: *Self, ptr: *Section, ret_addr: usize) !void {
        if (ptr.first_address[1] != ret_addr) {
            ptr.first_address[1] = ret_addr;
            ptr.stack_trace[1].instruction_addresses = &ptr.stack_trace_buf[1];
            ptr.stack_trace[1].index = 0;
            std.debug.captureStackTrace(ret_addr, &ptr.stack_trace[1]);
        }
        _ = self.list_pusher.pop();
    }
};

const Section = struct {
    tag: [:0]const u8,
    label: [:0]const u8,
    name: [:0]const u8,
    clock: time.Clock = .{},
    pause_clock: time.Clock = .{},
    idx: usize = 0,
    last_update_idx: usize = 0,
    window_avg: u32 = 0,
    sample_avg: u32 = 0,
    sample_max: u32 = 0,
    sample_min: u32 = 0,
    max: u32 = 0,
    min: u32 = 0,
    flags: packed struct {
        state: SectionState = .ended,
        section_type: SectionType,
    },
    first_address: [2]usize = @splat(std.math.maxInt(usize)),
    stack_trace: [2]std.builtin.StackTrace = undefined,
    buf: [frametime_buf_count]u32 = @splat(0),
    sample_avgs: [frame_stats_count]u32 = @splat(0),
    sample_maxes: [frame_stats_count]u32 = @splat(0),
    sample_mins: [frame_stats_count]u32 = @splat(0),
    stack_trace_buf: [2][stack_trace_count]usize = undefined,

    fn init(
        tag: [:0]const u8,
        label: [:0]const u8,
        name: [:0]const u8,
        comptime section_type: SectionType,
    ) Section {
        return .{
            .tag = tag,
            .label = label,
            .name = name,
            .flags = .{ .section_type = section_type },
        };
    }

    pub fn begin(self: *Section) void {
        self.clock.start(time.getNano());
        self.pause_clock.reset();
        self.flags.state = .began;
    }

    pub fn beginPaused(self: *Section) void {
        const now = time.getNano();
        self.clock.start(now);
        self.clock.pause(&self.pause_clock, now);
        self.flags.state = .began_paused;
    }

    pub fn end(self: *Section) void {
        const now = time.getNano();
        if (self.pause_clock.isRunning()) self.clock.unpause(&self.pause_clock, now);
        self.buf[frametime_mask.offset(self.idx)] = @intCast(self.clock.elapsed(now));
        self.clock.reset();
        self.idx += 1;
        self.flags.state = .ended;
    }

    pub fn pause(self: *Section) void {
        self.clock.pause(&self.pause_clock, time.getNano());
        self.flags.state = .ended;
    }

    pub fn unpause(self: *Section) void {
        self.clock.unpause(&self.pause_clock, time.getNano());
    }

    fn avgTime(self: *const Section) time.Time {
        return .{ .ns = self.window_avg };
    }

    fn updateStats(self: *Section) void {
        if (self.idx == 0) {
            @branchHint(.cold);
            return;
        }
        if (self.last_update_idx == self.idx) {
            @branchHint(.cold);
            self.last_update_idx = self.idx - 1;
        }
        if (self.min == 0) {
            @branchHint(.cold);
            self.min = std.math.maxInt(u32);
        }

        var acc: u64 = 0;
        var max: u32 = 0;
        var min: u32 = std.math.maxInt(u32);
        for (self.last_update_idx..self.idx) |n| {
            const val = self.buf[frametime_mask.offset(n)];
            acc += val;
            max = @max(max, val);
            min = @min(min, val);
        }

        self.sample_avg = @intCast(acc / (self.idx - self.last_update_idx));
        self.sample_max = max;
        self.sample_min = min;
        self.max = @max(self.max, self.sample_max);
        self.min = @min(self.min, self.sample_min);

        const end_idx = @min(self.idx, frametime_buf_count);

        acc = 0;
        for (0..end_idx) |n| acc += self.buf[n];
        self.window_avg = @intCast(acc / end_idx);

        @memmove(self.sample_avgs[0 .. frame_stats_count - 1], self.sample_avgs[1..]);
        self.sample_avgs[frame_stats_count - 1] = self.sample_avg;
        @memmove(self.sample_maxes[0 .. frame_stats_count - 1], self.sample_maxes[1..]);
        self.sample_maxes[frame_stats_count - 1] = self.sample_max;
        @memmove(self.sample_mins[0 .. frame_stats_count - 1], self.sample_mins[1..]);
        self.sample_mins[frame_stats_count - 1] = self.sample_min;

        self.last_update_idx = self.idx;
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
    try empty_section.register();
}

pub fn commitGraph() !void {
    assert(is_init);
    assert(!is_constructed);

    global_state.sections.lockPointers();
    var iter = global_state.sections.iterator();
    while (iter.next()) |i| _ = try switch (i.value_ptr.*.flags.section_type) {
        .root => global_state.tree.insertWithOrder(
            i.key_ptr.*,
            &.{ .key = i.key_ptr.*, .value = i.value_ptr.* },
            .ordered,
        ),
        .call, .sub => global_state.tree.insertWithOrder(
            i.key_ptr.*,
            &.{ .key = i.key_ptr.*, .value = i.value_ptr.* },
            .insert_last,
        ),
    };
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

pub fn reset() void {
    assert(is_init);
    global_state.reset();
}

pub fn updateStats(now: u64, comptime force_update: bool) void {
    assert(is_init);
    assert(is_constructed);

    global_state.updateStats(now, force_update);
}

pub fn logPerf() void {
    assert(is_init);
    assert(is_constructed);

    log.info("framerate: {}", .{framerate()});

    const Log = struct {
        fn iterTree(node: *const SectionsTree.Node, label: []const u8) void {
            if (node.value) |index| {
                log.debug("{s}{c}{s}{c} ~{D}", .{
                    global.spaces(node.depth),
                    opener(index.value.flags.section_type),
                    label,
                    closer(index.value.flags.section_type),
                    index.value.window_avg,
                });
            } else {
                log.debug("{s}[{s}]", .{ global.spaces(node.depth), label });
            }

            var edge_node = node.edges.first;
            while (edge_node != null) : (edge_node = edge_node.?.next) {
                const edge: *const SectionsTree.Edge = @fieldParentPtr("edge_node", edge_node.?);
                iterTree(&edge.target, edge.label);
            }
        }

        fn iterList(node: *const SectionsListTree.Node) void {
            const section_type = node.value.value.flags.section_type;
            const key = switch (section_type) {
                .root, .call => node.value.key,
                .sub => blk: {
                    var iter = std.mem.splitBackwardsScalar(u8, node.value.key, '.');
                    break :blk iter.first();
                },
            };
            log.debug("{s}{c}{s}{c} {D}", .{
                global.spaces(node.depth),
                opener(section_type),
                key,
                closer(section_type),
                node.value.value.window_avg,
            });

            if (node.edges.first) |child| iterList(@fieldParentPtr("edge_node", child));
            if (node.edge_node.next) |next| iterList(@fieldParentPtr("edge_node", next));
        }

        fn opener(section_type: SectionType) u8 {
            return switch (section_type) {
                .root => '[',
                .call => '<',
                .sub => '{',
            };
        }

        fn closer(section_type: SectionType) u8 {
            return switch (section_type) {
                .root => ']',
                .call => '>',
                .sub => '}',
            };
        }
    };

    log.debug("average:", .{});
    Log.iterTree(global_state.tree.root, "");

    if (global_state.active_list.edges.first) |first| {
        log.debug("call graph:", .{});
        Log.iterList(@fieldParentPtr("edge_node", first));
    }

    log.info("render / frame: {d:.2}%", .{
        math.percent(
            getAvg("gfx.Renderer.render").toFloat().asValue() /
                getAvg("main.main.frame").toFloat().asValue(),
        ),
    });
}

pub inline fn framerate() u32 {
    assert(is_init);
    return global_state.framerate;
}

pub inline fn frameratesAvg() []const u32 {
    assert(is_init);
    return global_state.framerates_avg;
}

pub inline fn frameratesMin() []const u32 {
    assert(is_init);
    return global_state.framerates_min;
}

pub inline fn frameratesMax() []const u32 {
    assert(is_init);
    return global_state.framerates_max;
}

pub inline fn updateStatsTimes() []const u32 {
    assert(is_init);
    return global_state.update_stats_times;
}

pub inline fn framesPerSample() u32 {
    assert(is_init);
    return global_state.frames_per_sample;
}

pub inline fn getAvg(label: []const u8) time.Time {
    assert(is_init);
    assert(is_constructed);
    if (global_state.sections.get(label)) |value| return value.avgTime();
    unreachable;
}

pub fn getSection(tag: []const u8) *Section {
    assert(is_init);
    const self = global_state.sections.get(tag);
    assert(self != null);
    return self.?;
}

pub inline fn sectionsTree() *const SectionsTree {
    return &global_state.tree;
}

pub inline fn sectionsListTree() *const SectionsListTree {
    return &global_state.active_list;
}

pub fn sections(comptime this: type, comptime labels: []const @TypeOf(.enum_literal)) type {
    comptime var label_names: []const [:0]const u8 = &[_][:0]const u8{};
    inline for (labels) |label| label_names = label_names ++ [_][:0]const u8{@tagName(label)};
    return TaggedSections(@typeName(this), label_names, sectionLabel(null, @typeName(this), .root), .root);
}

fn TaggedSections(
    comptime this: [:0]const u8,
    comptime labels: []const [:0]const u8,
    comptime this_label: [:0]const u8,
    comptime section_type: SectionType,
) type {
    const sub_type = subSectionType(section_type);
    comptime var struct_fields: []const std.builtin.Type.StructField = &[_]std.builtin.Type.StructField{};
    comptime var enum_fields: []const std.builtin.Type.EnumField = &[_]std.builtin.Type.EnumField{};
    var idx = 0;
    inline for (labels) |label| {
        const SubSectionType = TaggedSection(this, label, this_label, sub_type);
        struct_fields = struct_fields ++ [_]std.builtin.Type.StructField{.{
            .name = label[0.. :0],
            .type = type,
            .default_value_ptr = &SubSectionType,
            .is_comptime = true,
            .alignment = @alignOf(SubSectionType),
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
            inline for (labels) |label| try subTag(label).register();
        }

        pub fn sub(comptime label: Label) type {
            return subTag(@tagName(label));
        }

        fn subTag(comptime sub_tag: [:0]const u8) type {
            return TaggedSection(this, sub_tag, this_label, sub_type);
        }

        pub fn avgs() std.EnumArray(Label, time.Time) {
            var result: std.EnumArray(Label, time.Time) = undefined;
            inline for (labels, 0..) |label, n| result.set(@enumFromInt(n), subTag(label).avg());
            return result;
        }
    };
}

pub fn section(comptime this: type) type {
    return TaggedSection(null, @typeName(this), null, .root);
}

fn TaggedSection(
    comptime _parent_tag: ?[:0]const u8,
    comptime _tag: [:0]const u8,
    comptime parent_label: ?[:0]const u8,
    comptime section_type: SectionType,
) type {
    const sub_type = subSectionType(section_type);
    return struct {
        pub const tag = if (_parent_tag) |parent_tag| parent_tag ++ "." ++ _tag else _tag;
        pub const label = sectionLabel(parent_label, _tag, section_type);
        pub const name = sectionName(_tag, section_type);

        pub fn register() !void {
            assert(is_init);
            assert(!is_constructed);
            const value = try allocators.arena(.perf).create(Section);
            errdefer allocators.arena(.perf).destroy(value);
            value.* = .init(tag, label, name, section_type);
            try global_state.sections.putNoClobber(allocators.arena(.perf), tag, value);
        }

        pub fn sub(comptime sub_label: @TypeOf(.enum_literal)) type {
            return TaggedSection(tag, @tagName(sub_label), label, sub_type);
        }

        fn subTag(comptime sub_tag: []const u8) type {
            return TaggedSection(tag, sub_tag, label, sub_type);
        }

        pub fn sections(comptime sub_labels: []const @TypeOf(.enum_literal)) type {
            comptime var label_names: []const [:0]const u8 = &[_][:0]const u8{};
            inline for (sub_labels) |sub_label| label_names = label_names ++ [_][:0]const u8{@tagName(sub_label)};
            return TaggedSections(tag, label_names, label, sub_type);
        }

        pub fn push() void {
            global_state.beginSection(tag, getPtr(), @returnAddress()) catch unreachable;
        }

        pub fn pop() void {
            global_state.endSection(getPtr(), @returnAddress()) catch unreachable;
        }

        pub fn begin() void {
            const ptr = getPtr();
            global_state.beginSection(tag, ptr, @returnAddress()) catch unreachable;
            ptr.begin();
        }

        pub fn beginPaused() void {
            getPtr().beginPaused();
        }

        pub fn end() void {
            const ptr = getPtr();
            if (ptr.flags.state == .began) {
                global_state.endSection(ptr, @returnAddress()) catch unreachable;
            }
            ptr.end();
        }

        pub fn pause() void {
            const ptr = getPtr();
            if (ptr.flags.state == .began_paused) {
                global_state.endSection(ptr, @returnAddress()) catch unreachable;
            }
            ptr.pause();
        }

        pub fn unpause() void {
            const ptr = getPtr();
            if (ptr.flags.state == .began_paused) {
                global_state.beginSection(tag, ptr, @returnAddress()) catch unreachable;
            }
            ptr.unpause();
        }

        pub fn last() time.Time {
            assert(is_constructed);
            return .{ .ns = getPtr().last };
        }

        pub fn avg() time.Time {
            assert(is_constructed);
            return .{ .ns = getPtr().avg };
        }

        pub fn startTime() time.Time {
            assert(is_constructed);
            return .{ .ns = getPtr().clock.start_time };
        }

        pub fn getPtr() *Section {
            assert(is_init);
            const self = global_state.sections.get(tag);
            assert(self != null);
            return self.?;
        }
    };
}

fn subSectionType(comptime section_type: SectionType) SectionType {
    return switch (section_type) {
        .root => .call,
        .call => .sub,
        .sub => .sub,
    };
}

fn sectionLabel(comptime parent_label: ?[:0]const u8, comptime tag: [:0]const u8, comptime section_type: SectionType) [:0]const u8 {
    if (comptime parent_label) |pl| {
        return switch (comptime section_type) {
            .root => pl ++ "." ++ tag,
            .call => pl ++ "." ++ tag ++ "()",
            .sub => pl ++ "." ++ tag,
        };
    } else {
        return sectionName(tag, section_type);
    }
}

fn sectionName(comptime tag: [:0]const u8, comptime section_type: SectionType) [:0]const u8 {
    return switch (comptime section_type) {
        .root => tag,
        .call => tag ++ "()",
        .sub => "." ++ tag,
    };
}
