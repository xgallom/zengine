//!
//! Zengine SDL helper functions
//!

const std = @import("std");
const assert = std.debug.assert;

pub fn sliceFrom(gpa: std.mem.Allocator, items: anytype) ![]SDLTypePtr(@TypeOf(items)) {
    if (items.len == 0) return &.{};
    const result = try gpa.alloc(SDLTypePtr(@TypeOf(items)), items.len);
    if (comptime sdlNeedsAllocatorPtr(@TypeOf(items))) {
        for (result, items) |*to, *from| to.* = try from.toSDL(gpa);
    } else {
        for (result, items) |*to, *from| to.* = from.toSDL();
    }
    return result;
}

pub fn sdlNeedsAllocator(comptime T: type) bool {
    assert(@typeInfo(T) == .@"struct");
    assert(@hasDecl(T, "toSDL"));
    const ToSDL = @TypeOf(T.toSDL);
    assert(@typeInfo(ToSDL) == .@"fn");
    const params_len = @typeInfo(ToSDL).@"fn".params.len;
    assert(params_len <= 2 and params_len > 0);
    return params_len == 2;
}

pub fn sdlNeedsAllocatorPtr(comptime T: type) bool {
    return sdlNeedsAllocator(std.meta.Child(T));
}

pub fn SDLType(comptime T: type) type {
    assert(@typeInfo(T) == .@"struct");
    assert(@hasDecl(T, "toSDL"));
    const ToSDL = @TypeOf(T.toSDL);
    assert(@typeInfo(ToSDL) == .@"fn");
    const ReturnType = @typeInfo(ToSDL).@"fn".return_type.?;
    return if (sdlNeedsAllocator(T)) @typeInfo(ReturnType).error_union.payload else ReturnType;
}

pub fn SDLTypePtr(comptime T: type) type {
    return SDLType(std.meta.Child(T));
}
