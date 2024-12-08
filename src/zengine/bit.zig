pub fn Mask(comptime size: usize) type {
    return struct {
        const Self = @This();
        const mask: usize = size -% 1;
    };
}
