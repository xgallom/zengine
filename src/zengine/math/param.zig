//!
//! The zengine batching math parametrized functions implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");
const scalarT = @import("scalar.zig").scalarT;

pub fn paramT(comptime T: type) type {
    return struct {
        pub const Self = types.ParamT(T);
        pub const Scalar = T;

        const param = @This();
        pub const scalar = scalarT(T);

        pub const get = struct {
            pub fn lerp(comptime t0: Scalar, comptime t1: Scalar) Self {
                return Impl("lerp", .{ t0, t1 });
            }

            pub fn reverse() Self {
                return Impl("reverse", .{});
            }

            pub fn ease(comptime e: types.Ease, comptime f: Self) Self {
                return struct {
                    fn impl(t: Scalar) Scalar {
                        switch (comptime e) {
                            .in => f(t),
                            .out => param.reverse(f(param.reverse(t))),
                            // TODO: Implement .in_out
                            .in_out => @compileError("In-out easing not implemented"),
                        }
                    }
                }.impl;
            }

            fn Impl(comptime field: [:0]const u8, args: anytype) Self {
                return struct {
                    fn impl(t: Scalar) Scalar {
                        return @call(.always_inline, @field(param, field), .{t} ++ args);
                    }
                }.impl;
            }
        };

        pub inline fn lerp(t: Scalar, t0: Scalar, t1: Scalar) Scalar {
            return t0 * reverse(t) + t1 * t;
        }

        pub inline fn reverse(t: Scalar) Scalar {
            return scalar.one - t;
        }
    };
}
