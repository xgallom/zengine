//!
//! Zengine SDL helper functions
//!

const std = @import("std");
const assert = std.debug.assert;

pub fn sliceFrom(gpa: std.mem.Allocator, items: anytype) ![]SDLType(@TypeOf(items)) {
    if (items.len == 0) return &.{};
    const result = try gpa.alloc(SDLType(@TypeOf(items)), items.len);
    if (comptime sdlNeedsAllocator(@TypeOf(items))) {
        for (result, items) |*to, *from| to.* = try from.toSDL(gpa);
    } else {
        for (result, items) |*to, *from| to.* = from.toSDL();
    }
    return result;
}

pub fn sdlNeedsAllocator(comptime T: type) bool {
    assert(@typeInfo(std.meta.Child(T)) == .@"struct");
    assert(@hasDecl(std.meta.Child(T), "toSDL"));
    const ToSDL = @TypeOf(std.meta.Child(T).toSDL);
    assert(@typeInfo(ToSDL) == .@"fn");
    const params_len = @typeInfo(ToSDL).@"fn".params.len;
    assert(params_len <= 2 and params_len > 0);
    return params_len == 2;
}

pub fn SDLType(comptime T: type) type {
    assert(@typeInfo(std.meta.Child(T)) == .@"struct");
    assert(@hasDecl(std.meta.Child(T), "toSDL"));
    const ToSDL = @TypeOf(std.meta.Child(T).toSDL);
    assert(@typeInfo(ToSDL) == .@"fn");
    const ReturnType = @typeInfo(ToSDL).@"fn".return_type.?;
    return if (sdlNeedsAllocator(T)) @typeInfo(ReturnType).error_union.payload else ReturnType;
}
