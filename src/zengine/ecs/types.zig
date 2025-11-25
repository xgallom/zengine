const std = @import("std");
pub const FlagsBitSet = std.DynamicBitSetUnmanaged;

pub const ComponentFlagsBitSet = std.StaticBitSet(512);
pub const ComponentFlag = u32;

pub const Entity = u32;
pub const null_entity: Entity = 0;

pub const Id = enum(u64) {
    invalid = 0,
    _,

    pub const Meta = enum(u16) { invalid, valid };
    pub const Gen = u16;
    pub const Idx = u32;
    pub const Decomposed = packed struct(u64) {
        meta: Meta = .valid,
        gen: Gen,
        idx: Idx,
    };

    pub inline fn compose(id: Decomposed) Id {
        return @enumFromInt(@as(u64, @bitCast(id)));
    }

    pub inline fn decompose(id: Id) Decomposed {
        return @bitCast(@intFromEnum(id));
    }

    pub inline fn isValid(id: Id) bool {
        return id != .invalid;
    }

    pub inline fn gen(id: Id) Idx {
        return id.decompose().gen;
    }

    pub inline fn idx(id: Id) Idx {
        return id.decompose().idx;
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const d = self.decompose();
        switch (d.meta) {
            .invalid => _ = try writer.write("invalid"),
            .valid => try writer.print("{}@{}", .{ d.idx, d.gen }),
        }
    }
};
