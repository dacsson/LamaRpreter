//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const runtime = @cImport({
    @cInclude("runtime.h");
});
const bt = @import("bytecode.zig");
const dt = @import("disbyte.zig");
const Interpreter = @import("interpreter.zig");

pub const parse = dt.parse;
pub const dump = dt.dump;
pub const Instruction = bt.Instruction;

/// Main interpreter loop
pub fn run(allocator: *std.mem.Allocator, file_path: []const u8) !void {
    const bf = try parse(allocator, file_path);
    try dump(bf);
    const interpreter = try Interpreter.Interpreter.new(allocator, bf);
    try interpreter.run();
}
