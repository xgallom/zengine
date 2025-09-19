//!
//! The zengine ui module
//!

const std = @import("std");

pub const PropertyEditor = @import("ui/property_editor.zig").PropertyEditor;
pub const PropertyEditorWindow = @import("ui/PropertyEditorWindow.zig");
pub const UI = @import("ui/UI.zig");

test {
    std.testing.refAllDecls(@This());
}
