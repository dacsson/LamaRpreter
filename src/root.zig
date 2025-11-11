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
    defer {
        allocator.free(bf.code_section);
        bf.public_symbols.deinit(allocator.*);
        for (bf.string_table.items) |item| {
            allocator.free(item);
        }
        bf.string_table.deinit(allocator.*);
        allocator.destroy(bf);
    }

    try dump(bf);
    const interpreter = try Interpreter.Interpreter.new(allocator, bf, .{ .max_stack_size = 1024 * 1024, .parse_only = false });
    try interpreter.run();
}

/// Parse only, useful for debugging and testing.
/// Returns a list of decoded instructions, collected during parsing.
pub fn run_parse(allocator: *std.mem.Allocator, file_path: []const u8) !std.ArrayList(bt.Instruction) {
    const bf = try parse(allocator, file_path);
    defer {
        allocator.free(bf.code_section);
        bf.public_symbols.deinit(allocator.*);
        for (bf.string_table.items) |item| {
            allocator.free(item);
        }
        bf.string_table.deinit(allocator.*);
        allocator.destroy(bf);
    }

    try dump(bf);
    const interpreter = try Interpreter.Interpreter.new(allocator, bf, .{ .max_stack_size = 1024 * 1024, .parse_only = true });
    defer {
        // interpreter.instructions.deinit(allocator.*);
        interpreter.operand_stack.deinit(allocator.*);
        allocator.destroy(interpreter);
    }
    try interpreter.run();

    return interpreter.instructions;
}
