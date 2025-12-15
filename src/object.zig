const std = @import("std");
pub const __builtin = @import("std").zig.c_translation.builtins;
pub const __helpers = @import("std").zig.c_translation.helpers;
const gc = @cImport({
    @cInclude("gc.h");
});
const util = @import("util.zig");

const ObjectError = error{
    InvalidType,
    OutOfBoundsAccess,
};

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

    pub fn from_ptr(ptr: *anyopaque) Object {
        const as_int = @intFromPtr(ptr);
        const as_long: i64 = @intCast(as_int);
        return Object{ .data = as_long };
    }

    pub fn unbox(self: *Object) Object {
        return Object.from_int(UNBOX(self.data));
    }

    pub fn box(self: *Object) Object {
        return Object.from_int((self.data << 1) | 1);
    }

    fn to_ptr(self: *Object) *anyopaque {
        const as_usize: usize = @intCast(self.data);
        return @ptrFromInt(as_usize);
    }

    fn get_type(self: *Object) gc.lama_type {
        // get_type_header_ptr(get_obj_header_ptr(get_ptr()));
        const header_ptr = gc.get_obj_header_ptr(self.to_ptr()).?;
        const type_header = gc.get_type_header_ptr(header_ptr);
        return type_header;
    }

    pub fn is_aggregate(self: *Object) bool {
        switch (self.get_type()) {
            gc.ARRAY, gc.STRING, gc.SEXP => return true,
            else => return false,
        }
    }

    pub fn get_at(self: *Object, index: usize) !Object {
        // Check for invalid type
        if (!self.is_aggregate()) return ObjectError.InvalidType;

        // Check if boxed
        // if (!self.is_boxed)

        const as_data = util.TO_DATA(self.data);
        // const content : []u8 = util.contents(as_data);
        const len = gc.LEN(as_data.*.data_header);

        // Check for out-of-bounds access
        std.debug.assert(index >= 0);
        std.debug.assert(index < len);

        switch (self.get_type()) {
            gc.STRING => {
                const content: [*c]u8 = util.contents(as_data);
                return Object.from_int(@intCast(content[index]));
            },
            else => @panic("unimplemented!"),
        }

        return ObjectError.InvalidType;
    }

    pub fn set_at(self: *Object, index: usize, value: *Object) !void {
        // Check for invalid type
        if (!self.is_aggregate()) return ObjectError.InvalidType;

        // Check if boxed
        // if (!self.is_boxed)

        const as_data = util.TO_DATA(self.data);
        const len = gc.LEN(as_data.*.data_header);

        // Check for out-of-bounds access
        std.debug.assert(index >= 0);
        std.debug.assert(index < len);

        switch (self.get_type()) {
            gc.STRING => {
                const content: [*c]u8 = util.contents(as_data);
                content[index] = @intCast(value.data);
            },
            else => @panic("unimplemented!"),
        }
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
