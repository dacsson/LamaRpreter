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
    is_int: bool,

    /// Stores raw integer value
    pub fn from_int(x: i64) Object {
        // Make sure runtime detects it as unboxed

        return Object{ .data = x, .is_int = true };
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
        return Object{ .data = as_long, .is_int = false };
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
            gc.ARRAY => {
                const content: [*c]i64 = @ptrCast(@alignCast(util.contents(as_data)));
                const el = content + index;
                return Object.from_int(el.*);
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
            gc.ARRAY => {
                const content: [*c]i64 = @ptrCast(@alignCast(util.contents(as_data)));
                const el = content + index;
                el.* = value.data;
            },
            else => @panic("unimplemented!"),
        }
    }

    pub fn to_string(self: *Object, allocator: std.mem.Allocator) ![]u8 {
        // Ints are always unboxed
        if (self.is_int) {
            return try std.fmt.allocPrint(allocator, "{d}", .{self.data});
        }

        util.dbgs("agregate to_string self {} | {}\n", .{ self, gc.UNBOXED(self.data) });

        if (!self.is_aggregate()) {
            return ObjectError.InvalidType;
        }

        const as_data = util.TO_DATA(self.data);
        const len = gc.LEN(as_data.*.data_header);
        var str = std.ArrayList(u8).empty;
        defer str.deinit(allocator);

        switch (self.get_type()) {
            gc.STRING => {
                const content: [*c]u8 = util.contents(as_data);
                const to_z_string: []u8 = std.mem.span(content);

                try str.appendSlice(allocator, "\"");
                try str.appendSlice(allocator, to_z_string);
                try str.appendSlice(allocator, "\"");

                return str.toOwnedSlice(allocator);
            },
            gc.ARRAY => {
                const content: [*c]i64 = @ptrCast(@alignCast(util.contents(as_data)));

                const slice = content[0..len];
                util.dbgs("array to_string slice {any}\n", .{slice});

                try str.appendSlice(allocator, "[");

                util.dbgs("array to_string len {d}\n", .{len});

                for (0..len) |index| {
                    var obj_el = Object.from_int(slice[index]);
                    util.dbgs("array to_string el {d}\n", .{slice[index]});
                    const to_str = try obj_el.to_string(allocator);
                    try str.appendSlice(allocator, to_str);
                    if (index != len - 1) {
                        try str.appendSlice(allocator, ", ");
                    }
                }
                try str.appendSlice(allocator, "]");

                return str.toOwnedSlice(allocator);
            },
            gc.SEXP => {
                const content: [*c]i64 = @ptrCast(@alignCast(util.contents(as_data)));

                const slice = content[0..len];
                util.dbgs("sexp to_string slice {any}\n", .{slice});

                try str.appendSlice(allocator, "(");

                util.dbgs("array to_string len {d}\n", .{len});

                for (0..len) |index| {
                    const slice_index: usize = @intCast(slice[index]);
                    var obj_el = Object.from_ptr(@ptrFromInt(slice_index));
                    util.dbgs("array to_string el {d}\n", .{slice[index]});
                    const to_str = try obj_el.to_string(allocator);
                    try str.appendSlice(allocator, to_str);
                    if (index != len - 1) {
                        try str.appendSlice(allocator, ", ");
                    }
                }
                try str.appendSlice(allocator, ")");

                return str.toOwnedSlice(allocator);
            },
            else => @panic("unimplemented!"),
        }

        unreachable;
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
