//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const runtime = @cImport({
    @cInclude("runtime.h");
});
const bt = @import("bytecode.zig");
const dt = @import("disbyte.zig");

pub const parse = dt.parse;
pub const dump = dt.dump;
