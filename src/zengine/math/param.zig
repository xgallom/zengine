//!
//! The zengine parametrized functions
//!

const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");
const scalarT = @import("scalar.zig").scalarT;

const log = std.log.scoped(.math_param);

/// Parametrization of a generic type.
/// These implementations are inline and will optimize down into a single expression.
pub fn paramT(comptime T: type) type {
    return struct {
        /// Parametric operation
        pub const Self = types.ParamT(T);
        pub const Scalar = T;

        const param = @This();
        pub const scalar = scalarT(T);

        // TODO: Bezier curves

        /// These operations are not inline and are composable into operation chains.
        /// In release these should still compile down into a single expression.
        pub const op = struct {
            /// Zero operation.
            pub fn zero(t: Scalar) Scalar {
                _ = t;
                return scalar.zero;
            }

            /// One operation.
            pub fn one(t: Scalar) Scalar {
                _ = t;
                return scalar.one;
            }

            /// Negative one operation.
            pub fn negOne(t: Scalar) Scalar {
                _ = t;
                return scalar.neg_one;
            }

            /// Pass unmodified operation.
            pub fn pass(t: Scalar) Scalar {
                return t;
            }

            pub fn abs(t: Scalar) Scalar {
                return @abs(t);
            }

            pub const sin = impl("sin", .{});
            pub const cos = impl("cos", .{});
            pub const sqrt = impl("sqrt", .{});

            /// Chain two operations, outer after inner.
            pub fn chain(comptime o: Self, comptime i: Self) Self {
                return impl("chain", .{ o, i });
            }

            /// Multiply two operations.
            pub fn mul(comptime f: Self, comptime g: Self) Self {
                return impl("mul", .{ f, g });
            }

            /// Scale operation by parameter.
            pub fn scale(comptime f: Self) Self {
                return impl("scale", .{f});
            }

            /// Scale operation by reverse parameter.
            pub fn reverseScale(comptime f: Self) Self {
                return impl("reverseScale", .{f});
            }

            /// Reverse operation.
            pub fn reverse(t: Scalar) Scalar {
                return param.reverse(t);
            }

            /// Reverses operation.
            pub fn reversed(comptime f: Self) Self {
                return impl("reversed", .{f});
            }

            /// Linear interpolation.
            pub fn lerp(t0: Scalar, t1: Scalar) Self {
                return impl("lerp", .{ t0, t1 });
            }

            /// Weighted blend between two operations.
            pub fn blend(comptime f0: Self, comptime f1: Self, w: Scalar) Self {
                return impl("blend", .{ f0, f1, w });
            }

            /// Computes N-th integral power.
            pub fn pow(comptime N: comptime_int) Self {
                return impl("pow", .{N});
            }

            /// Computes P-th power as a blend between floor(P) and ceil(P).
            /// This isn't very exact but heavily outperforms float pow implementation.
            pub fn fpow(comptime P: comptime_float) Self {
                return impl("fpow", .{P});
            }

            /// N-th degree bezier curve starting in 0 and ending in 1.
            pub fn bezier01(comptime N: comptime_int, cs: [N - 1]Scalar) Self {
                return impl("bezier01", .{ N, cs });
            }

            /// N-th degree bezier curve.
            pub fn bezier(comptime N: comptime_int, cs: [N + 1]Scalar) Self {
                return impl("bezier", .{ N, cs });
            }

            /// Transforms an easing operation.
            pub fn ease(comptime e: types.Ease, comptime f: Self) Self {
                return impl("ease", .{ e, f });
            }

            fn impl(comptime field: [:0]const u8, args: anytype) Self {
                return struct {
                    fn impl(t: Scalar) Scalar {
                        return @call(.always_inline, @field(param, field), args ++ .{t});
                    }
                }.impl;
            }
        };

        pub inline fn sin(t: Scalar) Scalar {
            const tp = t - @floor(t / scalar.pi) * scalar.pi;
            const to = t / scalar.pi / scalar.init(2) - @floor(t / scalar.pi / scalar.init(2));
            const sgn = if (std.math.modf(to).fpart >= scalar.init(0.5)) scalar.neg_one else scalar.one;
            const tr = tp * (scalar.pi - tp);
            return sgn * scalar.init(16) * tr / (scalar.init(5) * scalar.pi * scalar.pi - scalar.init(4) * tr);
        }

        pub inline fn cos(t: Scalar) Scalar {
            return sin(t + scalar.pi / scalar.init(2));
        }

        pub inline fn sqrt(t: Scalar) Scalar {
            return fpow(0.5, t);
        }

        /// Chains two operations, outer after inner.
        pub inline fn chain(comptime o: Self, comptime i: Self, t: Scalar) Scalar {
            return o(i(t));
        }

        /// Multiply two operations.
        pub inline fn mul(comptime f: Self, comptime g: Self, t: Scalar) Scalar {
            return f(t) * g(t);
        }

        /// Scale operation by parameter.
        pub inline fn scale(comptime f: Self, t: Scalar) Scalar {
            return f(t) * t;
        }

        /// Scale operation by reverse parameter.
        pub inline fn reverseScale(comptime f: Self, t: Scalar) Scalar {
            return f(t) * reverse(t);
        }

        /// Reverse operation.
        pub inline fn reverse(t: Scalar) Scalar {
            assert01(t);
            return scalar.one - t;
        }

        inline fn reversed(comptime f: Self, t: Scalar) Scalar {
            return reverse(f(t));
        }

        /// Linear interpolation.
        pub inline fn lerp(t0: Scalar, t1: Scalar, t: Scalar) Scalar {
            return t0 * reverse(t) + t1 * t;
        }

        /// Weighted blend between two operations.
        pub inline fn blend(comptime f0: Self, comptime f1: Self, w: Scalar, t: Scalar) Scalar {
            return lerp(f0(t), f1(t), w);
        }

        /// Computes n-th integral power of t.
        pub inline fn pow(comptime N: comptime_int, t: Scalar) Scalar {
            comptime assert(N >= 0);

            return switch (comptime N) {
                0 => if (t < std.math.floatEps(Scalar)) scalar.zero else scalar.one,
                1 => t,
                2 => t * t,
                3 => t * t * t,
                4 => t * t * t * t,
                5 => t * t * t * t * t,
                6 => t * t * t * t * t * t,
                7 => t * t * t * t * t * t * t,
                8 => t * t * t * t * t * t * t * t,
                9 => t * t * t * t * t * t * t * t * t,
                10 => t * t * t * t * t * t * t * t * t * t,
                11 => t * t * t * t * t * t * t * t * t * t * t,
                12 => t * t * t * t * t * t * t * t * t * t * t * t,
                13 => t * t * t * t * t * t * t * t * t * t * t * t * t,
                14 => t * t * t * t * t * t * t * t * t * t * t * t * t * t,
                15 => t * t * t * t * t * t * t * t * t * t * t * t * t * t * t,
                inline else => blk: {
                    var result = scalar.one;
                    inline for (0..N) |_| result *= t;
                    break :blk result;
                },
            };
        }

        /// Compute up to N-th powers of t into an array.
        pub inline fn pows(comptime N: comptime_int, t: Scalar) [N + 1]Scalar {
            comptime assert(N >= 0);
            var result: [N + 1]Scalar = undefined;
            result[0] = scalar.one;
            inline for (0..N) |n| result[n + 1] = result[n] * t;
            return result;
        }

        /// Computes p-th power as a blend between floor(p) and ceil(p).
        /// This isn't exact but heavily outperforms float pow implementation.
        pub inline fn fpow(comptime P: comptime_float, t: Scalar) Scalar {
            comptime assert(P > 0);
            const N0: comptime_int = @intFromFloat(@floor(P));
            const N1: comptime_int = @intFromFloat(@ceil(P));
            if (comptime N0 == N1) {
                return pow(N0, t);
            } else {
                const w: comptime_float = P - @floor(P);
                const t0 = if (N0 == 0 and t < scalar.one) bezier01(3, .{
                    scalar.init(1.35),
                    scalar.init(0.85),
                }, t) else pow(N0, t);
                return lerp(t0, pow(N1, t), w);
            }
        }

        /// Transforms an easing operation.
        pub inline fn ease(comptime e: types.Ease, comptime f: Self, t: Scalar) Scalar {
            return switch (comptime e) {
                .in => f(t),
                .out => reverse(f(reverse(t))),
                .in_out => lerp(f(t), reverse(f(reverse(t))), t),
            };
        }

        /// N-th degree bezier curve in 0 and ending in 1.
        pub inline fn bezier01(comptime N: comptime_int, cs: [N - 1]Scalar, t: Scalar) Scalar {
            comptime assert(N >= 2);
            assert01(t);
            const bs = comptime binoms(N);
            const ts = pows(N, t);
            const rts = pows(N, reverse(t));
            return switch (comptime N) {
                2 => bs[1] * cs[0] * rts[1] * ts[1] + ts[2],
                3 => bs[1] * cs[0] * rts[2] * ts[1] + bs[2] * cs[1] * rts[1] * ts[2] + ts[3],
                4 => bs[1] * cs[0] * rts[3] * ts[1] + bs[2] * cs[1] * rts[2] * ts[2] + bs[3] * cs[2] * rts[1] * ts[3] +
                    ts[4],
                5 => bs[1] * cs[0] * rts[4] * ts[1] + bs[2] * cs[1] * rts[3] * ts[2] + bs[3] * cs[2] * rts[2] * ts[3] +
                    bs[4] * cs[3] * rts[1] * ts[4] + ts[5],
                6 => bs[1] * cs[0] * rts[5] * ts[1] + bs[2] * cs[1] * rts[4] * ts[2] + bs[3] * cs[2] * rts[3] * ts[3] +
                    bs[4] * cs[3] * rts[2] * ts[4] + bs[5] * cs[4] * rts[1] * ts[5] + ts[6],
                7 => bs[1] * cs[0] * rts[6] * ts[1] + bs[2] * cs[1] * rts[5] * ts[2] + bs[3] * cs[2] * rts[4] * ts[3] +
                    bs[4] * cs[3] * rts[3] * ts[4] + bs[5] * cs[4] * rts[2] * ts[5] + bs[6] * cs[5] * rts[1] * ts[6] +
                    ts[7],
                inline else => blk: {
                    var result = ts[N];
                    inline for (1..N) |n| result += bs[n] * cs[n - 1] * rts[N - n] * ts[n];
                    break :blk result;
                },
            };
        }

        /// N-th degree bezier curve.
        pub inline fn bezier(comptime N: comptime_int, cs: [N + 1]Scalar, t: Scalar) Scalar {
            comptime assert(N >= 1);
            const bs = comptime binoms(N);
            const ts = pows(N, t);
            const rts = pows(N, reverse(t));
            var result = scalar.zero;
            inline for (0..N + 1) |n| result += bs[n] * cs[n] * rts[N - n] * ts[n];
            return result;
        }

        pub fn binom(comptime N: comptime_int, comptime K: comptime_int) comptime_int {
            comptime assert(N >= 0);
            comptime assert(K <= N);
            return binoms(N)[K];
        }

        pub fn binoms(comptime N: comptime_int) [N + 1]Scalar {
            comptime assert(N >= 0);
            return switch (N) {
                0 => .{1},
                1 => .{ 1, 1 },
                inline else => blk: {
                    const prev = binoms(N - 1);
                    var result: [N + 1]Scalar = undefined;
                    result[0] = prev[0];
                    result[N] = prev[N - 1];
                    inline for (1..N) |n| result[n] = prev[n - 1] + prev[n];
                    break :blk result;
                },
            };
        }

        fn assert01(t: Scalar) void {
            assert(t >= 0);
            assert(t <= 1);
        }
    };
}

test "param" {
    const param = paramT(types.Scalar);
    const eps = std.math.floatEps(types.Scalar);
    {
        const zero = param.op.zero;
        try std.testing.expectEqual(0, zero(0));
        try std.testing.expectEqual(0, zero(0.2));
        try std.testing.expectEqual(0, zero(0.5));
        try std.testing.expectEqual(0, zero(0.8));
        try std.testing.expectEqual(0, zero(1));
    }
    {
        const one = param.op.one;
        try std.testing.expectEqual(1, one(0));
        try std.testing.expectEqual(1, one(0.2));
        try std.testing.expectEqual(1, one(0.5));
        try std.testing.expectEqual(1, one(0.8));
        try std.testing.expectEqual(1, one(1));
    }
    {
        const negOne = param.op.negOne;
        try std.testing.expectEqual(-1, negOne(0));
        try std.testing.expectEqual(-1, negOne(0.2));
        try std.testing.expectEqual(-1, negOne(0.5));
        try std.testing.expectEqual(-1, negOne(0.8));
        try std.testing.expectEqual(-1, negOne(1));
    }
    {
        const pass = param.op.pass;
        try std.testing.expectEqual(0, pass(0));
        try std.testing.expectEqual(0.2, pass(0.2));
        try std.testing.expectEqual(0.5, pass(0.5));
        try std.testing.expectEqual(0.8, pass(0.8));
        try std.testing.expectEqual(1, pass(1));
    }
    {
        const abs = param.op.abs;
        try std.testing.expectEqual(0, abs(0));
        try std.testing.expectEqual(0.2, abs(0.2));
        try std.testing.expectEqual(0.5, abs(0.5));
        try std.testing.expectEqual(0.8, abs(0.8));
        try std.testing.expectEqual(1, abs(1));
        try std.testing.expectEqual(0.2, abs(-0.2));
        try std.testing.expectEqual(0.5, abs(-0.5));
        try std.testing.expectEqual(0.8, abs(-0.8));
        try std.testing.expectEqual(1, abs(-1));
    }
    {
        const chain = param.op.chain(param.op.pow(2), param.op.reverse);
        try std.testing.expectEqual(1, chain(0));
        try std.testing.expectApproxEqAbs(0.64, chain(0.2), eps);
        try std.testing.expectApproxEqAbs(0.25, chain(0.5), eps);
        try std.testing.expectApproxEqAbs(0.04, chain(0.8), eps);
        try std.testing.expectEqual(0, chain(1));
    }
    {
        const mul = param.op.mul(param.op.pow(2), param.op.reverse);
        try std.testing.expectEqual(0, mul(0));
        try std.testing.expectApproxEqAbs(0.032, mul(0.2), eps);
        try std.testing.expectApproxEqAbs(0.125, mul(0.5), eps);
        try std.testing.expectApproxEqAbs(0.128, mul(0.8), eps);
        try std.testing.expectEqual(0, mul(1));
    }
    {
        const scale = param.op.scale(param.op.one);
        try std.testing.expectEqual(0, scale(0));
        try std.testing.expectEqual(0.2, scale(0.2));
        try std.testing.expectEqual(0.5, scale(0.5));
        try std.testing.expectEqual(0.8, scale(0.8));
        try std.testing.expectEqual(1, scale(1));
    }
    {
        const reverseScale = param.op.reverseScale(param.op.one);
        try std.testing.expectEqual(1, reverseScale(0));
        try std.testing.expectApproxEqAbs(0.8, reverseScale(0.2), eps);
        try std.testing.expectApproxEqAbs(0.5, reverseScale(0.5), eps);
        try std.testing.expectApproxEqAbs(0.2, reverseScale(0.8), eps);
        try std.testing.expectEqual(0, reverseScale(1));
    }
    {
        const reverse = param.op.reverse;
        try std.testing.expectEqual(1, reverse(0));
        try std.testing.expectApproxEqAbs(0.8, reverse(0.2), eps);
        try std.testing.expectApproxEqAbs(0.5, reverse(0.5), eps);
        try std.testing.expectApproxEqAbs(0.2, reverse(0.8), eps);
        try std.testing.expectEqual(0, reverse(1));
    }
    {
        const reversed = param.op.reversed(param.op.pow(2));
        try std.testing.expectEqual(1, reversed(0));
        try std.testing.expectApproxEqAbs(0.96, reversed(0.2), eps);
        try std.testing.expectApproxEqAbs(0.75, reversed(0.5), eps);
        try std.testing.expectApproxEqAbs(0.36, reversed(0.8), eps);
        try std.testing.expectEqual(0, reversed(1));
    }
    {
        const lerp = param.op.lerp(-2, 2);
        try std.testing.expectEqual(-2, lerp(0));
        try std.testing.expectApproxEqAbs(-1.2, lerp(0.2), eps);
        try std.testing.expectApproxEqAbs(0, lerp(0.5), eps);
        try std.testing.expectApproxEqAbs(1.2, lerp(0.8), eps);
        try std.testing.expectEqual(2, lerp(1));
    }
    {
        const blend = param.op.blend(param.op.pass, param.op.reverse, 0.2);
        try std.testing.expectEqual(0.2, blend(0));
        try std.testing.expectApproxEqAbs(0.32, blend(0.2), eps);
        try std.testing.expectApproxEqAbs(0.5, blend(0.5), eps);
        try std.testing.expectApproxEqAbs(0.68, blend(0.8), eps);
        try std.testing.expectEqual(0.8, blend(1));
    }
    {
        const pow = param.op.pow(1);
        try std.testing.expectEqual(0, pow(0));
        try std.testing.expectEqual(0.2, pow(0.2));
        try std.testing.expectEqual(0.5, pow(0.5));
        try std.testing.expectEqual(0.8, pow(0.8));
        try std.testing.expectEqual(1, pow(1));
    }
    {
        const pow = param.op.pow(2);
        try std.testing.expectEqual(0, pow(0));
        try std.testing.expectApproxEqAbs(0.04, pow(0.2), eps);
        try std.testing.expectApproxEqAbs(0.25, pow(0.5), eps);
        try std.testing.expectApproxEqAbs(0.64, pow(0.8), eps);
        try std.testing.expectEqual(1, pow(1));
    }
    {
        const pow = param.op.pow(3);
        try std.testing.expectEqual(0, pow(0));
        try std.testing.expectApproxEqAbs(0.008, pow(0.2), eps);
        try std.testing.expectApproxEqAbs(0.125, pow(0.5), eps);
        try std.testing.expectApproxEqAbs(0.512, pow(0.8), eps);
        try std.testing.expectEqual(1, pow(1));
    }
    {
        const pow = param.op.pow(4);
        try std.testing.expectEqual(0, pow(0));
        try std.testing.expectApproxEqAbs(0.0016, pow(0.2), eps);
        try std.testing.expectApproxEqAbs(0.0625, pow(0.5), eps);
        try std.testing.expectApproxEqAbs(0.4096, pow(0.8), eps);
        try std.testing.expectEqual(1, pow(1));
    }
    {
        const pow = param.op.pow(5);
        try std.testing.expectEqual(0, pow(0));
        try std.testing.expectApproxEqAbs(0.00032, pow(0.2), eps);
        try std.testing.expectApproxEqAbs(0.03125, pow(0.5), eps);
        try std.testing.expectApproxEqAbs(0.32768, pow(0.8), eps);
        try std.testing.expectEqual(1, pow(1));
    }
    {
        const pow = param.op.pow(6);
        try std.testing.expectEqual(0, pow(0));
        try std.testing.expectApproxEqAbs(0.000064, pow(0.2), eps);
        try std.testing.expectApproxEqAbs(0.015625, pow(0.5), eps);
        try std.testing.expectApproxEqAbs(0.262144, pow(0.8), eps);
        try std.testing.expectEqual(1, pow(1));
    }
    {
        const pow = param.op.pow(7);
        try std.testing.expectEqual(0, pow(0));
        try std.testing.expectApproxEqAbs(0.0000128, pow(0.2), eps);
        try std.testing.expectApproxEqAbs(0.0078125, pow(0.5), eps);
        try std.testing.expectApproxEqAbs(0.2097152, pow(0.8), eps);
        try std.testing.expectEqual(1, pow(1));
    }
    {
        const pow = param.op.pow(8);
        try std.testing.expectEqual(0, pow(0));
        try std.testing.expectApproxEqAbs(0.00000256, pow(0.2), eps);
        try std.testing.expectApproxEqAbs(0.00390625, pow(0.5), eps);
        try std.testing.expectApproxEqAbs(0.16777216, pow(0.8), eps);
        try std.testing.expectEqual(1, pow(1));
    }
    {
        const pow = param.op.pow(9);
        try std.testing.expectEqual(0, pow(0));
        try std.testing.expectApproxEqAbs(0.000000512, pow(0.2), eps);
        try std.testing.expectApproxEqAbs(0.001953125, pow(0.5), eps);
        try std.testing.expectApproxEqAbs(0.134217728, pow(0.8), eps);
        try std.testing.expectEqual(1, pow(1));
    }
    {
        const ts = param.pows(5, 0.2);
        try std.testing.expectEqual(1, ts[0]);
        try std.testing.expectApproxEqAbs(0.2, ts[1], eps);
        try std.testing.expectApproxEqAbs(0.04, ts[2], eps);
        try std.testing.expectApproxEqAbs(0.008, ts[3], eps);
        try std.testing.expectApproxEqAbs(0.0016, ts[4], eps);
        try std.testing.expectApproxEqAbs(0.00032, ts[5], eps);
    }
    {
        const fpow = param.op.fpow(2.2);
        try std.testing.expectEqual(0, fpow(0));
        try std.testing.expectApproxEqAbs(0.0336, fpow(0.2), eps);
        try std.testing.expectApproxEqAbs(0.225, fpow(0.5), eps);
        try std.testing.expectApproxEqAbs(0.6144, fpow(0.8), eps);
        try std.testing.expectEqual(1, fpow(1));
    }
    {
        const ease = param.op.ease(.in, param.op.pow(2));
        try std.testing.expectEqual(0, ease(0));
        try std.testing.expectApproxEqAbs(0.04, ease(0.2), eps);
        try std.testing.expectApproxEqAbs(0.25, ease(0.5), eps);
        try std.testing.expectApproxEqAbs(0.64, ease(0.8), eps);
        try std.testing.expectEqual(1, ease(1));
    }
    {
        const ease = param.op.ease(.out, param.op.pow(2));
        try std.testing.expectEqual(0, ease(0));
        try std.testing.expectApproxEqAbs(0.36, ease(0.2), eps);
        try std.testing.expectApproxEqAbs(0.75, ease(0.5), eps);
        try std.testing.expectApproxEqAbs(0.96, ease(0.8), eps);
        try std.testing.expectEqual(1, ease(1));
    }
    {
        const ease = param.op.ease(.in_out, param.op.pow(2));
        try std.testing.expectEqual(0, ease(0));
        try std.testing.expectApproxEqAbs(0.104, ease(0.2), eps);
        try std.testing.expectApproxEqAbs(0.5, ease(0.5), eps);
        try std.testing.expectApproxEqAbs(0.896, ease(0.8), eps);
        try std.testing.expectEqual(1, ease(1));
    }
    {
        const bezier01 = param.op.bezier01(3, .{ 1.35, 0.85 });
        try std.testing.expectEqual(0, bezier01(0));
        try std.testing.expectApproxEqAbs(0.608, bezier01(0.2), eps);
        try std.testing.expectApproxEqAbs(0.95, bezier01(0.5), eps);
        try std.testing.expectApproxEqAbs(0.968, bezier01(0.8), eps);
        try std.testing.expectEqual(1, bezier01(1));
    }
    {
        const bezier = param.op.bezier(3, .{ 1, 1.35, 0.85, 1 });
        try std.testing.expectEqual(1, bezier(0));
        try std.testing.expectApproxEqAbs(1.12, bezier(0.2), eps);
        try std.testing.expectApproxEqAbs(1.075, bezier(0.5), eps);
        try std.testing.expectApproxEqAbs(0.976, bezier(0.8), eps);
        try std.testing.expectEqual(1, bezier(1));
    }
    try std.testing.expectEqual(20, param.binom(6, 3));
    try std.testing.expectEqualSlices(types.Scalar, &.{ 1, 6, 15, 20, 15, 6, 1 }, &param.binoms(6));
}
