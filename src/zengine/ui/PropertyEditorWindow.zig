//!
//! The zengine property editor window ui
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const UI = @import("UI.zig");
const TreeFilter = @import("TreeFilter.zig");

const log = std.log.scoped(.ui_property_editor_window);
// pub const sections = perf.sections(@This(), &.{ .init, .draw });

allocator: std.mem.Allocator,
items: std.DoublyLinkedList = .{},
active_item: ?*const Item = null,
max_depth: u32 = 0,
is_open: bool = true,
filter: TreeFilter = .{},

const Self = @This();
pub const window_name = "Property Editor";

pub const Item = struct {
    self: *const Self,
    node: std.DoublyLinkedList.Node = .{},
    element: ?UI.Element = null,
    children: std.DoublyLinkedList = .{},
    depth: u32,
    id: [128]u8 = undefined,
    name: [128]u8 = undefined,

    fn draw(item: *Item, ui: *const UI, is_open: *bool) void {
        var walk = item.children.first;
        while (walk != null) : (walk = walk.?.next) {
            const child: *Item = @fieldParentPtr("node", walk.?);
            const width = child.sepWidth();

            c.igTableNextRow(0, 0);
            c.igPushID_Str(&child.id);

            _ = c.igTableNextColumn();
            c.igSeparatorEx(c.ImGuiSeparatorFlags_Horizontal, width);
            c.igAlignTextToFramePadding();
            c.igText(&child.name);
            c.igSeparatorEx(c.ImGuiSeparatorFlags_Horizontal, width);

            _ = c.igTableNextColumn();
            c.igSeparatorEx(c.ImGuiSeparatorFlags_Horizontal, width);
            c.igAlignTextToFramePadding();
            c.igText("");
            c.igSeparatorEx(c.ImGuiSeparatorFlags_Horizontal, width);

            ui.draw(child.element, is_open);

            c.igPopID();
        }
    }

    fn nodeElement(item: *Item) UI.Element {
        return .{
            .ptr = @ptrCast(item),
            .drawFn = @ptrCast(&Item.draw),
        };
    }

    fn sepWidth(item: *const Item) f32 {
        return 1 + @as(f32, @floatFromInt(item.self.max_depth - item.depth)) / 2;
    }
};

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    while (self.items.popFirst()) |node| self.destroy(node);
}

fn destroy(self: *const Self, node: *std.DoublyLinkedList.Node) void {
    const item: *Item = @fieldParentPtr("node", node);
    while (item.children.popFirst()) |child| self.destroy(child);
    self.allocator.destroy(item);
}

pub fn append(self: *Self, property_editor: anytype, id: []const u8, name: []const u8) !*Item {
    const result = try self.appendImpl(&self.items, .{
        .self = self,
        .element = property_editor.element(),
        .depth = 0,
    });
    _ = try std.fmt.bufPrintZ(&result.id, "{s}", .{id});
    _ = try std.fmt.bufPrintZ(&result.name, "{s}", .{name});
    return result;
}

pub fn appendNode(self: *Self, id: []const u8, name: []const u8) !*Item {
    const result = try self.appendImpl(&self.items, .{
        .self = self,
        .depth = 0,
    });
    // result.element = result.nodeElement();
    _ = try std.fmt.bufPrintZ(&result.id, "{s}", .{id});
    _ = try std.fmt.bufPrintZ(&result.name, "{s}", .{name});
    return result;
}

pub fn appendChild(self: *Self, item: *Item, property_editor: anytype, id: []const u8, name: []const u8) !*Item {
    const result = try self.appendImpl(&item.children, .{
        .self = self,
        .element = property_editor.element(),
        .depth = item.depth + 1,
    });
    _ = try std.fmt.bufPrintZ(&result.id, "{s}", .{id});
    _ = try std.fmt.bufPrintZ(&result.name, "{s}", .{name});
    return result;
}

pub fn appendChildNode(self: *Self, item: *Item, id: []const u8, name: []const u8) !*Item {
    const result = try self.appendImpl(&item.children, .{
        .self = self,
        .depth = item.depth + 1,
    });
    // result.element = result.nodeElement();
    _ = try std.fmt.bufPrintZ(&result.id, "{s}", .{id});
    _ = try std.fmt.bufPrintZ(&result.name, "{s}", .{name});
    return result;
}

fn appendImpl(self: *Self, items: *std.DoublyLinkedList, src_item: Item) !*Item {
    const item = try self.allocator.create(Item);
    errdefer self.allocator.destroy(item);
    item.* = src_item;
    self.max_depth = @max(self.max_depth, item.depth + 1);
    items.append(&item.node);
    return item;
}

pub fn draw(self: *Self, ui: *const UI, is_open: *bool) void {
    c.igSetNextWindowSize(.{ .x = 490, .y = 480 }, c.ImGuiCond_FirstUseEver);
    if (!c.igBegin(window_name, is_open, 0)) {
        c.igEnd();
        return;
    }

    if (c.igBeginChild_Str("##tree", .{ .x = 240 }, c.ImGuiChildFlags_ResizeX | c.ImGuiChildFlags_Borders | c.ImGuiChildFlags_NavFlattened, 0)) {
        self.filter.draw(ui, is_open);

        if (c.igBeginTable("##bg", 1, c.ImGuiTableFlags_RowBg, .{}, 0)) {
            var walk = self.items.first;
            while (walk != null) : (walk = walk.?.next) {
                const item: *const Item = @fieldParentPtr("node", walk.?);
                self.drawTreeNode(item, .init);
            }
            c.igEndTable();
        }
    }
    c.igEndChild();

    c.igSameLine(0, -1);

    c.igBeginGroup();
    if (self.active_item) |item| {
        const address = @intFromPtr(if (item.element) |el| el.ptr else null);
        c.igText("%s", &item.name);
        c.igTextDisabled("0x%08X (%s)", address, &item.id);
        c.igSeparatorEx(c.ImGuiSeparatorFlags_Horizontal, 1);
        if (c.igBeginTable("##properties", 2, c.ImGuiTableFlags_Resizable | c.ImGuiTableFlags_ScrollY, .{}, 0)) {
            c.igPushID_Str(&item.id);
            c.igTableSetupColumn("", c.ImGuiTableColumnFlags_WidthFixed, 90, 0);
            c.igTableSetupColumn("", c.ImGuiTableColumnFlags_WidthStretch, 2, 0);

            if (item.element) |el| ui.draw(el, is_open);

            c.igPopID();
            c.igEndTable();
        }
    }
    c.igEndGroup();

    c.igEnd();
}

fn drawTreeNode(
    self: *Self,
    item: *const Item,
    parent_filt_res: TreeFilter.Result,
) void {
    const filt_res = Filter.apply(&self.filter, item, parent_filt_res);
    if (filt_res == .not_found) return;

    c.igTableNextRow(0, 0);
    _ = c.igTableNextColumn();
    c.igPushID_Str(&item.id);

    var tree_flags: c.ImGuiTreeNodeFlags = c.ImGuiTreeNodeFlags_OpenOnArrow |
        c.ImGuiTreeNodeFlags_OpenOnDoubleClick |
        c.ImGuiTreeNodeFlags_NavLeftJumpsToParent |
        c.ImGuiTreeNodeFlags_SpanFullWidth |
        c.ImGuiTreeNodeFlags_DrawLinesToNodes;
    if (item == self.active_item) tree_flags |= c.ImGuiTreeNodeFlags_Selected;
    if (item.children.first == null) tree_flags |= c.ImGuiTreeNodeFlags_Leaf |
        c.ImGuiTreeNodeFlags_Bullet;

    self.filter.toggleOpen(filt_res);
    const node_open = c.igTreeNodeEx_StrStr("##node", tree_flags, "%s", &item.name);
    if (c.igIsItemFocused()) self.active_item = item;
    if (node_open) {
        var walk = item.children.first;
        while (walk != null) : (walk = walk.?.next) {
            const child: *const Item = @fieldParentPtr("node", walk.?);
            self.drawTreeNode(child, filt_res);
        }
        c.igTreePop();
    }
    c.igPopID();
}

const Filter = TreeFilter.Filter(*const Item, keyTree, walkTree, null);

fn keyTree(item: *const Item) ?[*:0]const u8 {
    return @ptrCast(&item.name);
}

fn walkTree(filter: *TreeFilter, item: *const Item) TreeFilter.Result {
    var walk = item.children.first;
    while (walk != null) : (walk = walk.?.next) {
        const result = Filter.applyWalk(filter, @fieldParentPtr("node", walk.?));
        if (result != .not_found) return .sub_passed;
    }
    return .not_found;
}

pub fn element(self: *Self) UI.Element {
    return .{
        .ptr = @ptrCast(self),
        .drawFn = @ptrCast(&draw),
    };
}
