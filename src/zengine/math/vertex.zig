//!
//! The zengine vertex implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const scalarT = @import("scalar.zig").scalarT;
const types = @import("types.zig");
const vectorNT = @import("vector.zig").vectorNT;

pub fn vertexNT(comptime N: comptime_int, comptime T: type) type {
    return struct {
        pub const Self = [len]Vector;
        pub const Vector = types.VectorNT(N, T);
        pub const Scalar = T;
        pub const Coords = types.CoordsNT(N, T);
        pub const len = types.VertexAttr.len;

        pub const scalar = scalarT(T);
        pub const vector = vectorNT(N, T);

        pub const zero = splat(vector.zero);
        pub const one = splat(vector.one);
        pub const neg_one = splat(vector.neg_one);
        pub const ntr_zero = splat(vector.ntr_zero);
        pub const ntr_fwd = splat(vector.ntr_fwd);
        pub const tr_zero = splat(vector.tr_zero);
        pub const tr_fwd = splat(vector.tr_fwd);

        pub const Map = struct {
            self: *Self,

            pub inline fn get(self: Map, comptime idx: types.VertexAttr) Vector {
                return self.self[@intFromEnum(idx)];
            }

            pub inline fn getPtr(self: Map, comptime idx: types.VertexAttr) *Vector {
                return &self.self[@intFromEnum(idx)];
            }

            pub inline fn getPtrConst(self: Map, comptime idx: types.VertexAttr) *const Vector {
                return &self.self[@intFromEnum(idx)];
            }

            pub inline fn set(self: Map, comptime idx: types.VertexAttr, value: *const Vector) void {
                self.getPtr(idx).* = value.*;
            }

            pub inline fn iterator(self: Map) Iterator {
                return .{ .self = self.self };
            }

            pub const Iterator = struct {
                self: *Self,
                idx: usize = 0,

                pub fn next(i: *Iterator) ?*Vector {
                    if (i.idx < len) {
                        defer i.idx += 1;
                        return &i.self[i.idx];
                    }
                    return null;
                }

                pub fn reset(i: *Iterator) void {
                    i.idx = 0;
                }
            };
        };

        pub const CMap = struct {
            self: *const Self,

            pub inline fn get(self: CMap, comptime idx: types.VertexAttr) Vector {
                return self.self[@intFromEnum(idx)];
            }

            pub inline fn getPtrConst(self: CMap, comptime idx: types.VertexAttr) *const Vector {
                return &self.self[@intFromEnum(idx)];
            }

            pub inline fn iterator(self: CMap) Iterator {
                return .{ .self = self.self };
            }

            pub const Iterator = struct {
                self: *const Self,
                idx: usize = 0,

                pub fn next(i: *Iterator) ?*const Vector {
                    if (i.idx < len) {
                        defer i.idx += 1;
                        return &i.self[i.idx];
                    }
                    return null;
                }

                pub fn reset(i: *Iterator) void {
                    i.idx = 0;
                }
            };
        };

        pub inline fn map(self: *Self) Map {
            return .{ .self = self };
        }

        pub inline fn cmap(self: *const Self) CMap {
            return .{ .self = self };
        }

        pub fn splat(value: Vector) Self {
            return @splat(value);
        }

        pub fn splatInto(result: *Self, value: Vector) void {
            result.* = @splat(value);
        }

        pub fn sliceLen(comptime L: usize, self: *Self) []Vector {
            comptime assert(L <= len);
            return self[0..L];
        }

        pub fn sliceLenConst(comptime L: usize, self: *const Self) []const Vector {
            comptime assert(L <= len);
            return self[0..L];
        }

        pub fn slice(self: *Self) []Vector {
            return sliceLen(len, self);
        }

        pub fn sliceConst(self: *const Self) []const Vector {
            return sliceLenConst(len, self);
        }
    };
}
