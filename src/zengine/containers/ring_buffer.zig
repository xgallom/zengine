//!
//! Zengine ring buffer implementation
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const math = @import("../math.zig");
const sched = @import("../sched.zig");

const log = std.log.scoped(.containers_thread_safe);

pub fn RingBuffer(comptime T: type, comptime N: comptime_int) type {
    assert(std.math.isPowerOfTwo(N));
    return struct {
        buffer: *[capacity]T = undefined,
        head: usize = 0,
        tail: usize = 0,

        const Self = @This();
        pub const Slice = [2][]T;
        pub const invalid: Self = .{};
        pub const capacity = N;
        pub const mask = math.IntMask(capacity);

        comptime {
            assert(mask.uses_mask);
        }

        pub fn init(gpa: Allocator) !Self {
            return .{ .buffer = @ptrCast(try gpa.alloc(T, capacity)) };
        }

        pub fn deinit(self: *Self, gpa: Allocator) void {
            gpa.free(self.allocatedSlice());
            self.* = .{};
        }

        pub fn length(self: @This()) usize {
            return self.head -% self.tail;
        }

        pub fn unusedCapacity(self: @This()) usize {
            return capacity - self.length();
        }

        pub fn allocatedSlice(self: @This()) []T {
            return self.buffer[0..capacity];
        }

        pub fn slice(self: @This()) Slice {
            if (self.tail == self.head) return .{ &.{}, &.{} };
            const start = mask.offset(self.tail);
            const end = mask.offset(self.head);
            const result = self.range(start, end);
            assert(result[0].len + result[1].len == self.length());
            return result;
        }

        pub fn unusedSlice(self: @This()) Slice {
            if (self.unusedCapacity() == 0) return .{ &.{}, &.{} };
            const start = mask.offset(self.head);
            const end = mask.offset(self.tail);
            const result = self.range(start, end);
            assert(result[0].len + result[1].len == self.unusedCapacity());
            return result;
        }

        /// Asserts start and end are within capacity.
        pub fn range(self: @This(), start: usize, end: usize) Slice {
            assert(start < capacity);
            assert(end < capacity);
            return if (start < end)
                .{ self.buffer[start..end], &.{} }
            else
                .{ self.buffer[start..capacity], self.buffer[0..end] };
        }

        /// Asserts slot is within current slice.
        pub fn get(self: @This(), idx: usize) T {
            assert(mask.offset(idx -% self.tail) < self.length());
            return self.buffer[mask.offset(idx)];
        }

        /// Asserts non-zero length.
        pub fn getFirst(self: @This()) T {
            assert(self.length() > 0);
            return self.buffer[mask.offset(self.tail)];
        }

        /// Asserts non-zero length.
        pub fn getLast(self: @This()) T {
            assert(self.length() > 0);
            return self.buffer[(self.head -% 1) & mask];
        }

        pub fn popFirst(self: *@This()) ?T {
            if (self.length() == 0) return null;
            defer self.tail +%= 1;
            return self.getFirst();
        }

        pub fn popLast(self: *@This()) ?T {
            if (self.length() == 0) return null;
            // Avoid two subtractions to not confuse the compiler.
            const prev_head = self.head -% 1;
            self.head = prev_head;
            return self.buffer[mask.offset(prev_head)];
        }

        pub fn reset(self: *@This()) void {
            self.head = 0;
            self.tail = 0;
        }

        pub fn prepend(self: *@This(), item: T) !void {
            if (self.unusedCapacity() == 0) return error.OutOfMemory;
            self.prependAssumeCapacity(item);
        }

        pub fn prependAssumeCapacity(self: *@This(), item: T) void {
            assert(self.unusedCapacity() > 0);
            // Avoid two subtractions to not confuse the compiler.
            const prev_tail = self.tail -% 1;
            self.tail = prev_tail;
            self.buffer[mask.offset(prev_tail)] = item;
        }

        pub fn append(self: *@This(), item: T) !void {
            if (self.unusedCapacity() == 0) return error.OutOfMemory;
            self.appendAssumeCapacity(item);
        }

        // Asserts the container is not full.
        pub fn appendAssumeCapacity(self: *@This(), item: T) void {
            assert(self.unusedCapacity() > 0);
            self.buffer[mask.offset(self.head)] = item;
            self.head +%= 1;
        }

        // Asserts container has enough free space.
        pub fn appendSliceAssumceCapacity(self: *@This(), buffer: []const T) void {
            assert(buffer.len <= self.unusedCapacity());
            if (buffer.len == 0) return;
            const start = mask.offset(self.head);
            const len_0 = capacity - start;
            if (buffer.len <= len_0) {
                @memcpy(self.buffer[start..][0..buffer.len], buffer);
            } else {
                const len_1 = buffer.len - len_0;
                @memcpy(self.buffer[start..], buffer[0..len_0]);
                @memcpy(self.buffer[0..len_1], buffer[len_0..]);
            }
            self.head +%= buffer.len;
        }

        pub fn iterator(self: @This()) Iterator {
            return .init(self);
        }

        pub const Iterator = struct {
            self: Self,

            pub fn init(self: Self) @This() {
                return .{ .self = self };
            }

            pub fn peek(i: *@This()) ?T {
                return if (i.self.length() > 0) i.self.getFirst() else null;
            }

            pub fn next(i: *@This()) ?T {
                return i.self.popFirst();
            }
        };

        pub fn writer(self: *@This(), buffer: []u8) Writer {
            return .init(self, buffer);
        }

        pub const Writer = if (T != u8)
            @compileError("The Writer interface is only defined for RingBuffer(u8) " ++
                "but the given type is RingBuffer(" ++ @typeName(T) ++ ")")
        else
            struct {
                self: *Self,
                interface: std.Io.Writer,
                err: ?Error = null,

                const max_buffers_len = 16;

                pub const Error = error{NoSpaceLeft};

                pub fn init(self: *Self, buffer: []u8) @This() {
                    return .{
                        .self = self,
                        .interface = .{
                            .vtable = &.{
                                .drain = drainFn,
                            },
                            .buffer = buffer,
                        },
                    };
                }

                fn drainFn(
                    io_w: *std.Io.Writer,
                    data: []const []const u8,
                    splat: usize,
                ) std.Io.Writer.Error!usize {
                    const w: *@This() = @fieldParentPtr("interface", io_w);
                    return w.drain(data, splat);
                }

                pub fn drain(
                    w: *@This(),
                    data: []const []const u8,
                    splat: usize,
                ) std.Io.Writer.Error!usize {
                    const buffered = w.interface.buffered();
                    var bufs: [max_buffers_len][]const u8 = undefined;
                    var len: usize = 0;
                    if (buffered.len > 0) {
                        bufs[len] = buffered;
                        len += 1;
                    }
                    for (data[0 .. data.len - 1]) |buf| {
                        bufs[len] = buf;
                        len += 1;
                        if (len >= bufs.len) break;
                    }
                    const pattern = data[data.len - 1];
                    if (len < bufs.len) switch (splat) {
                        0 => {},
                        1 => if (pattern.len > 0) {
                            bufs[len] = pattern;
                            len += 1;
                        },
                        else => switch (pattern.len) {
                            0 => {},
                            1 => {
                                const primary_buffer = w.interface.buffer[w.interface.end..];
                                var backup_buffer: [64]u8 = undefined;
                                const splat_buf = if (primary_buffer.len >= primary_buffer.len)
                                    primary_buffer
                                else
                                    &backup_buffer;
                                const memset_len = @min(splat_buf.len, splat);
                                const buf = splat_buf[0..memset_len];
                                @memset(buf, pattern[0]);
                                bufs[len] = buf;
                                len += 1;
                                var remaining_splat = splat - buf.len;
                                while (remaining_splat >= splat_buf.len and len < bufs.len) {
                                    assert(buf.len == splat_buf.len);
                                    bufs[len] = splat_buf;
                                    len += 1;
                                    remaining_splat -= splat_buf.len;
                                }
                                if (remaining_splat > 0 and len < bufs.len) {
                                    assert(buf.len == splat_buf.len);
                                    assert(remaining_splat < splat_buf.len);
                                    bufs[len] = splat_buf[0..remaining_splat];
                                    len += 1;
                                }
                            },
                            else => for (0..splat) |_| {
                                bufs[len] = pattern;
                                len += 1;
                                if (len >= bufs.len) break;
                            },
                        },
                    };
                    if (len == 0) return 0;
                    const cap = w.self.unusedCapacity();
                    var written: usize = 0;
                    for (bufs[0..len]) |buf| {
                        const unused = cap - written;
                        if (buf.len <= unused) {
                            w.self.appendSliceAssumceCapacity(buf);
                            written += buf.len;
                        } else {
                            w.self.appendSliceAssumceCapacity(buf[0..unused]);
                            _ = w.interface.consume(cap);
                            w.err = error.NoSpaceLeft;
                            return error.WriteFailed;
                        }
                    }
                    return w.interface.consume(written);
                }
            };

        pub fn reader(self: *@This()) Reader {
            const r_idx = self.tail.load(.monotonic);
            const w_idx = self.head.load(.acquire);
            return .{ .self = self, .w_idx = w_idx, .r_idx = r_idx };
        }

        pub const Reader = struct {
            self: *Self,
            interface: std.Io.Reader,
        };
    };
}
