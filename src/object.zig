const std = @import("std");
pub const __builtin = @import("std").zig.c_translation.builtins;
pub const __helpers = @import("std").zig.c_translation.helpers;

/// An element of operand stack in interpreter, really just a
/// number of wrappers + forced alignemt for gc
pub const Object = struct {
    data: i64 align(16),

    /// Stores raw integer value
    pub fn from_int(x: i64) Object {
        return Object{ .data = x };
    }

    /// Creates a c-compatible string ptr, wrapped in an
    /// c_ulong (i64) array, where first argument is the string pointer
    /// Made that way for Lama runtime compatibility, see Bstring function
    /// for reference
    pub fn from_string(str: []const u8) Object {
        var c_str: [*c]u8 = @ptrCast(@alignCast(@constCast(str.ptr)));
        c_str[str.len] = 0;
        const c_str_ptr = &c_str;
        const as_int = @intFromPtr(c_str_ptr);
        const first_arg: i64 = @intCast(as_int);
        return Object{ .data = first_arg };
    }

    pub fn unbox(self: *Object) Object {
        return Object.from_int(UNBOX(self.data));
    }

    pub fn UNBOXED(x: anytype) @TypeOf(__helpers.cast(c_long, x) & @as(c_int, 1)) {
        _ = &x;
        return __helpers.cast(c_long, x) & @as(c_int, 1);
    }
    pub fn UNBOX(x: anytype) @TypeOf(__helpers.cast(c_long, x) >> @as(c_int, 1)) {
        _ = &x;
        return __helpers.cast(c_long, x) >> @as(c_int, 1);
    }
    pub fn BOX(x: anytype) @TypeOf((__helpers.cast(c_long, x) << @as(c_int, 1)) | @as(c_int, 1)) {
        _ = &x;
        return (__helpers.cast(c_long, x) << @as(c_int, 1)) | @as(c_int, 1);
    }
};
