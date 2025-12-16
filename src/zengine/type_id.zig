//!
//! The zengine type id implementation
//!

const std = @import("std");

// pub const TypeId = enum(usize) { _ };
// const TypeIdPtr = *const struct { _: u8 };
pub const TypeId = *const struct { _: u8 };

pub inline fn typeId(comptime T: type) TypeId {
    const S = struct {
        comptime {
            _ = T;
        }
        var id: @typeInfo(TypeId).pointer.child = undefined;
    };
    return &S.id;
}
