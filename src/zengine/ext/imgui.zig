//!
//! The ImGui library
//!

pub const imgui = @cImport({
    @cInclude("cimgui.h");
});
