const std = @import("std");
pub const FlagsBitSet = std.DynamicBitSetUnmanaged;

pub const ComponentFlagsBitSet = std.StaticBitSet(512);
pub const ComponentFlag = u32;

pub const Entity = u32;
pub const null_entity: Entity = 0;
