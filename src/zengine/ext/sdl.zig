//!
//! The SDL3 library
//!

pub const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
});
