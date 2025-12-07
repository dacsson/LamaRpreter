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
