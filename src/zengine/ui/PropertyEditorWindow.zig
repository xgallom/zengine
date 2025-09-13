//!
//! The zengine property editor window ui
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const UI = @import("UI.zig");

const log = std.log.scoped(.ui_property_editor_window);
// pub const sections = perf.sections(@This(), &.{ .init, .draw });

allcator: std.mem.Allocator,
filter: c.ImGuiTextFilter = .{},
items: std.DoublyLinkedList = .{},
active_item: ?*const Item = null,
max_depth: u32 = 0,

pub const Self = @This();

pub const Item = struct {
    self: *const Self,
    node: std.DoublyLinkedList.Node = .{},
    id: [*:0]const u8,
    name: [*:0]const u8,
    element: UI.Element = undefined,
    children: std.DoublyLinkedList = .{},
    depth: u32,

    fn draw(item: *Item, ui: *const UI, is_open: *bool) void {
        var walk = item.children.first;
        while (walk != null) : (walk = walk.?.next) {
            const child: *Item = @fieldParentPtr("node", walk.?);

            c.igTableNextRow(0, 0);
            c.igPushID_Str(child.id);

            const width = child.sepWidth();

            _ = c.igTableNextColumn();
            c.igAlignTextToFramePadding();
            c.igText(child.name);
            c.igSeparatorEx(c.ImGuiSeparatorFlags_Horizontal, width);

            _ = c.igTableNextColumn();
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
            .draw = @ptrCast(&Item.draw),
        };
    }

    fn sepWidth(item: *const Item) f32 {
        return 1 + @as(f32, @floatFromInt(item.self.max_depth - item.depth)) / 2;
    }
};

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allcator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    while (self.items.popFirst()) |node| self.destroy(node);
}

fn destroy(self: *const Self, node: *std.DoublyLinkedList.Node) void {
    const item: *Item = @fieldParentPtr("node", node);
    while (item.children.popFirst()) |child| self.destroy(child);
    self.allcator.destroy(item);
}

pub fn append(self: *Self, property_editor: anytype) !*Item {
    return self.appendImpl(&self.items, .{
        .self = self,
        .id = @TypeOf(property_editor.*).component_id,
        .name = @TypeOf(property_editor.*).component_name,
        .element = property_editor.element(),
        .depth = 0,
    });
}

pub fn appendNode(self: *Self, id: [*:0]const u8, name: [*:0]const u8) !*Item {
    const result = try self.appendImpl(&self.items, .{
        .self = self,
        .id = id,
        .name = name,
        .depth = 0,
    });
    result.element = result.nodeElement();
    return result;
}

pub fn appendChild(self: *Self, item: *Item, property_editor: anytype) !*Item {
    self.max_depth = @max(self.max_depth, item.depth + 1);
    return self.appendImpl(&item.children, .{
        .self = self,
        .id = @TypeOf(property_editor).component_id,
        .name = @TypeOf(property_editor).component_name,
        .element = property_editor.element(),
        .depth = item.depth + 1,
    });
}

pub fn appendChildNode(self: *Self, item: *Item, id: [*:0]const u8, name: [*:0]const u8) !*Item {
    self.max_depth = @max(self.max_depth, item.depth + 1);
    const result = try self.appendImpl(&item.children, .{
        .self = self,
        .id = id,
        .name = name,
        .depth = item.depth + 1,
    });
    result.element = result.nodeElement();
    return result;
}

fn appendImpl(self: *const Self, items: *std.DoublyLinkedList, src_item: Item) !*Item {
    const item = try self.allcator.create(Item);
    errdefer self.allcator.destroy(item);
    item.* = src_item;
    items.append(&item.node);
    return item;
}

pub fn draw(self: *Self, ui: *const UI, is_open: *bool) void {
    c.igSetNextWindowSize(.{ .x = 480, .y = 450 }, c.ImGuiCond_FirstUseEver);
    if (!c.igBegin("Property Editor", is_open, 0)) {
        c.igEnd();
        return;
    }

    if (c.igBeginChild_Str("##tree", .{ .x = 300 }, c.ImGuiChildFlags_ResizeX | c.ImGuiChildFlags_Borders | c.ImGuiChildFlags_NavFlattened, 0)) {
        c.igSetNextItemWidth(-std.math.floatMin(f32));
        c.igSetNextItemShortcut(c.ImGuiMod_Ctrl | c.ImGuiKey_F, c.ImGuiInputFlags_Tooltip);
        c.igPushItemFlag(c.ImGuiItemFlags_NoNavDefaultFocus, true);
        if (c.igInputTextWithHint("##Filter", "incl, -excl", @ptrCast(&self.filter.InputBuf), self.filter.InputBuf.len, c.ImGuiInputTextFlags_EscapeClearsAll, null, null)) {
            c.ImGuiTextFilter_Build(&self.filter);
        }
        c.igPopItemFlag();

        if (c.igBeginTable("##bg", 1, c.ImGuiTableFlags_RowBg, .{}, 0)) {
            var walk = self.items.first;
            while (walk != null) : (walk = walk.?.next) {
                const item: *const Item = @fieldParentPtr("node", walk.?);
                if (c.ImGuiTextFilter_PassFilter(
                    &self.filter,
                    item.name,
                    null,
                )) self.drawTreeNode(item);
            }
            c.igEndTable();
        }
    }
    c.igEndChild();

    c.igSameLine(0, -1);

    c.igBeginGroup();
    if (self.active_item) |item| {
        c.igText("%s", item.name);
        c.igTextDisabled("0x%08X (%s)", @intFromPtr(item.element.ptr), item.id);
        c.igSeparatorEx(c.ImGuiSeparatorFlags_Horizontal, item.sepWidth());
        if (c.igBeginTable("##properties", 2, c.ImGuiTableFlags_Resizable | c.ImGuiTableFlags_ScrollY, .{}, 0)) {
            c.igPushID_Str(item.id);
            c.igTableSetupColumn("", c.ImGuiTableColumnFlags_WidthFixed, 50, 0);
            c.igTableSetupColumn("", c.ImGuiTableColumnFlags_WidthStretch, 2, 0);

            ui.draw(item.element, is_open);

            c.igPopID();
            c.igEndTable();
        }
    }
    c.igEndGroup();

    c.igEnd();
}

fn drawTreeNode(self: *Self, item: *const Item) void {
    c.igTableNextRow(0, 0);
    _ = c.igTableNextColumn();
    c.igPushID_Str(item.id);
    var tree_flags: c.ImGuiTreeNodeFlags = c.ImGuiTreeNodeFlags_OpenOnArrow |
        c.ImGuiTreeNodeFlags_OpenOnDoubleClick |
        c.ImGuiTreeNodeFlags_NavLeftJumpsToParent |
        c.ImGuiTreeNodeFlags_SpanFullWidth |
        c.ImGuiTreeNodeFlags_DrawLinesToNodes;
    if (item == self.active_item) tree_flags |= c.ImGuiTreeNodeFlags_Selected;
    if (item.children.first == null) tree_flags |= c.ImGuiTreeNodeFlags_Leaf |
        c.ImGuiTreeNodeFlags_Bullet;
    const node_open = c.igTreeNodeEx_StrStr("", tree_flags, "%s", item.name);
    if (c.igIsItemFocused()) self.active_item = item;
    if (node_open) {
        var walk = item.children.first;
        while (walk != null) : (walk = walk.?.next) {
            const child: *const Item = @fieldParentPtr("node", walk.?);
            self.drawTreeNode(child);
        }
        c.igTreePop();
    }
    c.igPopID();
}

pub fn element(self: *Self) UI.Element {
    return .{
        .ptr = @ptrCast(self),
        .draw = @ptrCast(&draw),
    };
}
