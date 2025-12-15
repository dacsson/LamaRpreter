pub const __builtin = @import("std").zig.c_translation.builtins;
pub const __helpers = @import("std").zig.c_translation.helpers;
pub const std = @import("std");
const builtin = @import("builtin");

pub const UtilError = error{
    EmptyArray,
    OutOfMemory,
};

pub inline fn UNBOXED(x: anytype) @TypeOf(__helpers.cast(c_long, x) & @as(c_int, 1)) {
    _ = &x;
    return __helpers.cast(c_long, x) & @as(c_int, 1);
}
pub inline fn UNBOX(x: anytype) @TypeOf(__helpers.cast(c_long, x) >> @as(c_int, 1)) {
    _ = &x;
    return __helpers.cast(c_long, x) >> @as(c_int, 1);
}
pub inline fn BOX(x: anytype) @TypeOf((__helpers.cast(c_long, x) << @as(c_int, 1)) | @as(c_int, 1)) {
    _ = &x;
    return (__helpers.cast(c_long, x) << @as(c_int, 1)) | @as(c_int, 1);
}

pub const DATA_HEADER_SZ = __helpers.sizeof(u64) + __helpers.sizeof(usize);

pub fn get_tag(arg_d: [*c]align(1) data) i64 {
    var d = arg_d;
    _ = &d;
    return @bitCast(@as(c_ulong, @truncate(d.*.data_header & @as(u64, 7))));
}
pub fn get_len(arg_d: [*c]align(1) data) i64 {
    var d = arg_d;
    _ = &d;
    return @bitCast(@as(c_ulong, @truncate((d.*.data_header & (@as(c_ulong, 18446744073709551615) ^ @as(c_ulong, 7))) >> @intCast(3))));
}

pub const data = extern struct {
    data_header: u64 = 0,
    forward_address: usize = 0,
    _contents: [0]u8 = @import("std").mem.zeroes([0]u8),
    pub const tag = get_tag;
    pub const len = get_len;
};

pub fn contents(self: *data) __helpers.FlexibleArrayType(@TypeOf(self), @typeInfo(@TypeOf(self.*._contents)).array.child) {
    return @ptrCast(@alignCast(&self.*._contents));
}

pub inline fn TO_DATA(x: anytype) [*c]data {
    _ = &x;
    return __helpers.cast([*c]data, __helpers.cast([*c]u8, x) - DATA_HEADER_SZ);
}

const DEBUG = builtin.mode == .Debug;

// debug logs that are removed from Release builds
pub inline fn dbgs(fmt: []const u8, args: anytype) void {
    if (DEBUG) {
        std.debug.print(fmt, args);
    }
}

pub fn prepend(array: *std.ArrayList(i32), allocator: *std.mem.Allocator, value: i32) !void {
    try array.insert(allocator.*, 0, value);
}

pub fn pop_head(array: *std.ArrayList(i32)) !i32 {
    if (array.items.len == 0) {
        return UtilError.EmptyArray;
    }
    const value = array.items[0];
    _ = array.orderedRemove(0);
    return value;
}
