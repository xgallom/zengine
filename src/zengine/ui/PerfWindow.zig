//!
//! The zengine performance monitoring window ui
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const perf = @import("../perf.zig");
const time = @import("../time.zig");
const plot_fmt = @import("plot_fmt.zig");
const TreeFilter = @import("TreeFilter.zig");
const UI = @import("UI.zig");

const log = std.log.scoped(.ui_perf_window);

allocator: std.mem.Allocator,
active_item: ?perf.Value = null,
max_depth: u32 = 0,
is_open: bool = true,
tab_bar: packed struct {
    module_tree: bool = true,
    call_graph: bool = false,
} = .{},
filter: TreeFilter = .{},

pub const Self = @This();
pub const window_name = "Performance";
var buf: [64]u8 = undefined;

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    while (self.items.popFirst()) |node| self.destroy(node);
}

pub fn draw(self: *Self, ui: *const UI, is_open: *bool) void {
    c.igSetNextWindowSize(.{ .x = 630, .y = 4 * 240 }, c.ImGuiCond_FirstUseEver);
    if (!c.igBegin(window_name, is_open, 0)) {
        c.igEnd();
        return;
    }

    self.drawPlots();
    self.drawInspector(ui, is_open);

    c.igEnd();
}

pub fn element(self: *Self) UI.Element {
    return .{
        .ptr = @ptrCast(self),
        .drawFn = @ptrCast(&draw),
    };
}

fn drawPlots(self: *Self) void {
    const times = perf.updateStatsTimes();

    if (c.ImPlot_BeginPlot(
        "Framerate##framerate_plot",
        .{ .x = c.igGetWindowWidth() - 30, .y = 240 },
        c.ImPlotFlags_NoFrame,
    )) {
        const framerates = perf.frameratesSlice();
        c.ImPlot_SetupAxes(
            "",
            "fps",
            c.ImPlotAxisFlags_AutoFit,
            c.ImPlotAxisFlags_AutoFit,
        );

        var max: u32 = 0;
        for (framerates) |peak| max = @max(max, peak);
        c.ImPlot_SetupAxisLimits(c.ImAxis_Y1, 0, @floatFromInt(max / 10 * 11), c.ImPlotCond_Always);

        plot_fmt.Time(.ms).apply(c.ImAxis_X1);

        c.ImPlot_PushStyleVar_Float(c.ImPlotStyleVar_FillAlpha, 0.25);

        self.drawPlotFilled("##framerates", times, framerates);

        c.ImPlot_EndPlot();

        c.igText(
            "Framerate: %d, Frames per sample: %d",
            framerates[framerates.len - 1],
            perf.framesPerSample(),
        );
    }

    if (c.ImPlot_BeginPlot(
        "Frame stats##frame_stats_plot",
        .{ .x = c.igGetWindowWidth() - 30, .y = 240 },
        // .{ .x = c.igCalcItemWidth() - 34, .y = 240 },
        c.ImPlotFlags_NoFrame,
    )) {
        const item = if (self.active_item) |item| item else perf.getSection("perf.empty");
        const sample_avgs: []const u32 = &item.sample_avgs;
        const sample_maxes: []const u32 = &item.sample_maxes;
        const sample_mins: []const u32 = &item.sample_mins;

        c.ImPlot_SetupAxis(c.ImAxis_X1, "", c.ImPlotAxisFlags_AutoFit);
        c.ImPlot_SetupAxis(c.ImAxis_Y1, "frame time", c.ImPlotAxisFlags_AutoFit);

        var max: u32 = 0;
        for (sample_maxes) |v| max = @max(max, v);
        c.ImPlot_SetupAxisLimits(c.ImAxis_Y1, 0, @floatFromInt(max / 10 * 11), c.ImPlotCond_Always);

        plot_fmt.Time(.ms).apply(c.ImAxis_X1);
        plot_fmt.Time(.ns).apply(c.ImAxis_Y1);

        c.ImPlot_PushStyleVar_Float(c.ImPlotStyleVar_FillAlpha, 0.25);

        self.drawPlotFilled("sample_avg", times, sample_avgs);
        self.drawPlotLine("sample_max", times, sample_maxes);
        self.drawPlotLine("sample_min", times, sample_mins);

        c.ImPlot_EndPlot();
    }
}

fn drawPlotFilled(self: *Self, label: [*:0]const u8, times: []const u32, samples: []const u32) void {
    c.ImPlot_PlotShaded_U32PtrU32PtrInt(
        label,
        times.ptr,
        samples.ptr,
        @intCast(samples.len),
        0,
        0,
        0,
        @sizeOf(u32),
    );
    self.drawPlotLine(label, times, samples);
}

fn drawPlotLine(
    _: *Self,
    label: [*:0]const u8,
    times: []const u32,
    samples: []const u32,
) void {
    c.ImPlot_PlotLine_U32PtrU32Ptr(
        label,
        times.ptr,
        samples.ptr,
        @intCast(samples.len),
        0,
        0,
        @sizeOf(u32),
    );
}

fn drawInspector(self: *Self, ui: *const UI, is_open: *bool) void {
    if (c.igBeginChild_Str(
        "##perf_sections",
        .{},
        c.ImGuiChildFlags_NavFlattened,
        0,
    )) {
        if (c.igBeginChild_Str(
            "##tree",
            .{ .x = 240 },
            c.ImGuiChildFlags_Borders | c.ImGuiChildFlags_ResizeX | c.ImGuiChildFlags_NavFlattened,
            0,
        )) {
            if (c.igBeginTabBar("##tab_bar", c.ImGuiTabBarFlags_None)) {
                if (c.igBeginTabItem(
                    "Module tree",
                    &self.tab_bar.module_tree,
                    c.ImGuiTabItemFlags_NoCloseButton,
                )) {
                    self.filter.draw(ui, is_open);
                    if (c.igBeginChild_Str("Module tree##tree", .{}, c.ImGuiChildFlags_NavFlattened, 0)) {
                        if (c.igBeginTable("##bg", 1, c.ImGuiTableFlags_RowBg, .{}, 0)) {
                            var walk = perf.sectionsTree().root.edges.first;
                            while (walk != null) : (walk = walk.?.next) {
                                const item: *const perf.SectionsTree.Edge = @fieldParentPtr(
                                    "edge_node",
                                    walk.?,
                                );
                                self.drawModuleTreeNode(item, .init);
                            }
                            c.igEndTable();
                        }
                    }
                    c.igEndChild();
                    c.igEndTabItem();
                }

                if (c.igBeginTabItem(
                    "Call graph",
                    &self.tab_bar.call_graph,
                    c.ImGuiTabItemFlags_NoCloseButton,
                )) {
                    self.filter.draw(ui, is_open);
                    if (c.igBeginChild_Str(
                        "Call graph##list",
                        .{},
                        c.ImGuiChildFlags_NavFlattened,
                        0,
                    )) {
                        if (c.igBeginTable("##bg", 1, c.ImGuiTableFlags_RowBg, .{}, 0)) {
                            var walk = perf.sectionsListTree().edges.first;
                            while (walk != null) : (walk = walk.?.next) {
                                const item: *const perf.SectionsListTree.Edge = @fieldParentPtr(
                                    "edge_node",
                                    walk.?,
                                );
                                self.drawCallGraphNode(item, .init);
                            }
                            c.igEndTable();
                        }
                    }
                    c.igEndChild();
                    c.igEndTabItem();
                }
            }
            c.igEndTabBar();
        }
        c.igEndChild();

        c.igSameLine(0, -1);

        c.igBeginGroup();
        if (self.active_item) |item| {
            c.igText("%s", item.label.ptr);
            c.igTextDisabled("0x%08X (%s)", @intFromPtr(item), item.tag.ptr);
            c.igSeparatorEx(c.ImGuiSeparatorFlags_Horizontal, 1);

            if (c.igBeginTable("##info", 2, c.ImGuiTableFlags_ScrollY, .{}, 0)) {
                c.igPushID_Str(item.tag.ptr);
                c.igTableSetupColumn("name", c.ImGuiTableColumnFlags_WidthFixed, 120, 0);
                c.igTableSetupColumn("value", c.ImGuiTableColumnFlags_WidthStretch, 0, 0);

                self.drawTableRow("##avg", "Window average", item.window_avg);
                self.drawTableRow("##sample_avg", "Sample average", item.sample_avg);
                self.drawTableRow("##sample_min", "Sample min", item.sample_min);
                self.drawTableRow("##sample_max", "Sample max", item.sample_max);
                self.drawTableRow("##min", "Min", item.min);
                self.drawTableRow("##max", "Max", item.max);

                c.igPopID();
                c.igEndTable();
            }
        }
        c.igEndGroup();
    }
    c.igEndChild();
}

fn drawTableRow(_: *Self, id: [*:0]const u8, name: [*:0]const u8, value: u32) void {
    c.igTableNextRow(0, 0);
    c.igPushID_Str(id);

    _ = c.igTableNextColumn();
    c.igAlignTextToFramePadding();
    c.igTextUnformatted(name, null);

    _ = c.igTableNextColumn();
    c.igAlignTextToFramePadding();
    const text = std.fmt.bufPrintZ(
        &buf,
        "{D}",
        .{value},
    ) catch unreachable;
    c.igTextUnformatted(text, null);

    c.igPopID();
}

fn drawModuleTreeNode(
    self: *Self,
    item: *const perf.SectionsTree.Edge,
    parent_filt_res: TreeFilter.Result,
) void {
    var label = item.label;
    if (item.target.value) |value| label = value.value.name;

    const filt_res = ModuleTreeFilter.apply(&self.filter, item, parent_filt_res);
    if (filt_res == .not_found) return;

    c.igTableNextRow(0, 0);
    _ = c.igTableNextColumn();
    c.igPushID_Str(item.label.ptr);

    var tree_flags: c.ImGuiTreeNodeFlags = c.ImGuiTreeNodeFlags_OpenOnArrow |
        c.ImGuiTreeNodeFlags_OpenOnDoubleClick |
        c.ImGuiTreeNodeFlags_NavLeftJumpsToParent |
        c.ImGuiTreeNodeFlags_SpanFullWidth |
        c.ImGuiTreeNodeFlags_DrawLinesToNodes;
    if (item.target.value) |value| {
        if (value.value == self.active_item) tree_flags |= c.ImGuiTreeNodeFlags_Selected;
    }
    if (item.target.edges.first == null) tree_flags |= c.ImGuiTreeNodeFlags_Leaf |
        c.ImGuiTreeNodeFlags_Bullet;

    self.filter.toggleOpen(filt_res);
    const node_open = c.igTreeNodeEx_StrStr("##node", tree_flags, "%s", label.ptr);

    if (item.target.value) |value| {
        if (c.igIsItemFocused()) self.active_item = value.value;
    }

    if (node_open) {
        var walk = item.target.edges.first;
        while (walk != null) : (walk = walk.?.next) {
            self.drawModuleTreeNode(@fieldParentPtr("edge_node", walk.?), filt_res);
        }
        c.igTreePop();
    }
    c.igPopID();
}

fn drawCallGraphNode(
    self: *Self,
    item: *const perf.SectionsListTree.Edge,
    parent_filt_res: TreeFilter.Result,
) void {
    const filt_res = CallGraphFilter.apply(&self.filter, item, parent_filt_res);
    if (filt_res == .not_found) return;

    const label = switch (item.value.value.flags.section_type) {
        .root, .call => item.value.value.label,
        .sub => item.value.value.name,
    };

    c.igTableNextRow(0, 0);
    _ = c.igTableNextColumn();
    c.igPushID_Str(item.value.key.ptr);

    var tree_flags: c.ImGuiTreeNodeFlags = c.ImGuiTreeNodeFlags_OpenOnArrow |
        c.ImGuiTreeNodeFlags_OpenOnDoubleClick |
        c.ImGuiTreeNodeFlags_NavLeftJumpsToParent |
        c.ImGuiTreeNodeFlags_SpanFullWidth |
        c.ImGuiTreeNodeFlags_DrawLinesToNodes;
    if (item.value.value == self.active_item) tree_flags |= c.ImGuiTreeNodeFlags_Selected;
    if (item.edges.first == null) tree_flags |= c.ImGuiTreeNodeFlags_Leaf |
        c.ImGuiTreeNodeFlags_Bullet;

    self.filter.toggleOpen(filt_res);
    const node_open = c.igTreeNodeEx_StrStr("##node", tree_flags, "%s", label.ptr);
    if (c.igIsItemFocused()) self.active_item = item.value.value;
    if (node_open) {
        var walk = item.edges.first;
        while (walk != null) : (walk = walk.?.next) {
            self.drawCallGraphNode(@fieldParentPtr("edge_node", walk.?), filt_res);
        }
        c.igTreePop();
    }
    c.igPopID();
}

const ModuleTreeFilter = TreeFilter.Filter(
    *const perf.SectionsTree.Edge,
    keyModuleTree,
    walkModuleTree,
    null,
);

fn keyModuleTree(item: *const perf.SectionsTree.Edge) ?[*:0]const u8 {
    if (item.target.value) |value| return @ptrCast(value.value.name);
    return @ptrCast(item.label);
}

fn walkModuleTree(filter: *TreeFilter, item: *const perf.SectionsTree.Edge) TreeFilter.Result {
    var walk = item.target.edges.first;
    while (walk != null) : (walk = walk.?.next) {
        const result = ModuleTreeFilter.applyWalk(filter, @fieldParentPtr("edge_node", walk.?));
        if (result != .not_found) return .sub_passed;
    }
    return .not_found;
}

const CallGraphFilter = TreeFilter.Filter(
    *const perf.SectionsListTree.Edge,
    keyCallGraph,
    walkCallGraph,
    null,
);

fn keyCallGraph(item: *const perf.SectionsListTree.Edge) ?[*:0]const u8 {
    return @ptrCast(item.value.value.name);
}

fn walkCallGraph(filter: *TreeFilter, item: *const perf.SectionsListTree.Edge) TreeFilter.Result {
    var walk = item.edges.first;
    while (walk != null) : (walk = walk.?.next) {
        const result = CallGraphFilter.applyWalk(filter, @fieldParentPtr("edge_node", walk.?));
        if (result != .not_found) return .sub_passed;
    }
    return .not_found;
}
