//!
//! External libraries
//!

pub const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cDefine("CIMGUI_USE_SDL3", "1");
    @cDefine("CIMGUI_USE_SDLGPU3", "1");

    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_image/SDL_image.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
    @cInclude("SDL3_ttf/SDL_textengine.h");
    @cInclude("SDL3_shadercross/SDL_shadercross.h");

    @cInclude("cimgui.h");
    @cInclude("cimgui_impl.h");
    @cInclude("cimplot.h");
});
