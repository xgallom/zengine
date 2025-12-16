//!
//! The zengine smooth value implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const perf = @import("../perf.zig");
const ui_mod = @import("../ui.zig");
const time = @import("../time.zig");
const lerp = @import("lerp.zig");

const log = std.log.scoped(.anim_smv);

pub fn Config(comptime T: type) type {
    return struct {
        lerp: lerp.LerpFn(T) = lerp.defaultLerpFn(T),
    };
}

pub const ExpDecayParams = struct {
    smooth_time: math.Scalar,

    fn get(self: *const @This(), dt: math.Scalar) math.Scalar {
        return 1 - std.math.exp(-dt / self.smooth_time);
    }
};

pub fn ExpDecay(comptime T: type, comptime config: Config(T)) type {
    return SmoothValue(T, ExpDecayParams, config);
}

pub fn SmoothValue(comptime T: type, comptime P: type, comptime config: Config(T)) type {
    return struct {
        current: T,
        target: T,
        params: Params,

        const Self = @This();
        pub const Params = P;

        pub fn init(value: T, params: Params) Self {
            return .{
                .current = value,
                .target = value,
                .params = params,
            };
        }

        pub fn setImmediate(self: *Self, value: T) void {
            self.current = value;
            self.target = value;
        }

        pub fn setTarget(self: *Self, target: T) void {
            self.target = target;
        }

        pub fn update(self: *Self, dt: math.Scalar) void {
            const t = self.params.get(dt);
            self.current = config.lerp(self.current, self.target, t);
        }
    };
}
