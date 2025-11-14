//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const bt = @import("bytecode.zig");
const dt = @import("disbyte.zig");
const intr = @import("interpreter.zig");

pub const Bytefile = dt.Bytefile;
pub const Instruction = bt.Instruction;
pub const Interpreter = intr.Interpreter;

/// Main interpreter loop
pub fn run(allocator: *std.mem.Allocator, file_path: []const u8) !void {
    const bf = try Bytefile.parse(allocator, file_path);
    defer bf.free(allocator);

    try bf.dump();
    const interpreter = try Interpreter.new(allocator, bf, .{ .max_stack_size = 1024 * 1024, .parse_only = false });
    try interpreter.run();
}

/// Parse only, useful for debugging and testing.
/// Returns a list of decoded instructions, collected during parsing.
pub fn run_parse(allocator: *std.mem.Allocator, file_path: []const u8) !std.ArrayList(bt.Instruction) {
    const bf = try Bytefile.parse(allocator, file_path);
    defer bf.free(allocator);

    try bf.dump();
    const interpreter = try Interpreter.new(allocator, bf, .{ .max_stack_size = 1024 * 1024, .parse_only = true });
    defer {
        // interpreter.instructions.deinit(allocator.*);
        interpreter.operand_stack.deinit(allocator.*);
        interpreter.call_stack.deinit(allocator.*);
        allocator.destroy(interpreter);
    }
    try interpreter.run();

    return interpreter.instructions;
}
