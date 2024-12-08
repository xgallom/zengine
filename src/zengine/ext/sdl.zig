//!
//! The SDL3 library
//!

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

pub usingnamespace c;
