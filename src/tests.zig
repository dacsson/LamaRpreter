const std = @import("std");
const LamaRpreter = @import("LamaRpreter");

// Parsing a binary (bytecode) file.
// only confirming the file is parsed correctly,
// not the instruction set
test "parse" {
    std.testing.refAllDecls(@This());

    var allocator = std.testing.allocator;

    const file_path = "test1.bc";

    // ~ =>  xxd dump/test1.bc
    // 00000000: 0500 0000 0100 0000 0100 0000 0000 0000  ................
    // 00000010: 0000 0000 6d61 696e 0052 0200 0000 0000  ....main.R......
    // 00000020: 0000 1002 0000 0010 0300 0000 015a 0100  .............Z..
    // 00000030: 0000 4000 0000 0018 5a02 0000 005a 0400  ..@.....Z....Z..
    // 00000040: 0000 2000 0000 0071 16ff                 .. ....q..
    const data = [_]u8{
        0x05, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x6d, 0x61, 0x69, 0x6e, 0x00, 0x52, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x10, 0x02, 0x00, 0x00, 0x00, 0x10, 0x03, 0x00, 0x00, 0x00, 0x01, 0x5a, 0x01, 0x00,
        0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x18, 0x5a, 0x02, 0x00, 0x00, 0x00, 0x5a, 0x04, 0x00,
        0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x00, 0x71, 0x16, 0xff,
    };

    // creates if doesnt exist, truncates if it does
    var file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
        std.debug.print("Failed to create file: {}\n", .{err});
        return err;
    };
    defer {
        file.close();
        std.fs.cwd().deleteFile(file_path) catch |err| {
            std.debug.print("Failed to delete file: {}\n", .{err});
        };
    }

    try file.writeAll(&data);

    const bf = try LamaRpreter.Bytefile.parse(&allocator, file_path);
    defer bf.free(&allocator);

    // Only a main function is present
    try std.testing.expect(std.mem.eql(u8, "main", bf.string_table.items[0]));
    try std.testing.expectEqual(@as(usize, 49), bf.code_section.len);
}

// Check instruction decoding process.
// Here we actually decode the instructions and verify their correctness
// a.k.a. placement, opcode and arguments in the code section.
test "decode" {
    std.testing.refAllDecls(@This());

    var allocator = std.testing.allocator;

    const file_path = "test1.bc";

    // ~ =>  xxd dump/test1.bc
    // 00000000: 0500 0000 0100 0000 0100 0000 0000 0000  ................
    // 00000010: 0000 0000 6d61 696e 0052 0200 0000 0000  ....main.R......
    // 00000020: 0000 1002 0000 0010 0300 0000 015a 0100  .............Z..
    // 00000030: 0000 4000 0000 0018 5a02 0000 005a 0400  ..@.....Z....Z..
    // 00000040: 0000 2000 0000 0071 16ff                 .. ....q..
    const data = [_]u8{
        0x05, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x6d, 0x61, 0x69, 0x6e, 0x00, 0x52, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x10, 0x02, 0x00, 0x00, 0x00, 0x10, 0x03, 0x00, 0x00, 0x00, 0x01, 0x5a, 0x01, 0x00,
        0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x18, 0x5a, 0x02, 0x00, 0x00, 0x00, 0x5a, 0x04, 0x00,
        0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x00, 0x71, 0x16, 0xff,
    };

    // creates if doesnt exist, truncates if it does
    var file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
        std.debug.print("Failed to create file: {}\n", .{err});
        return err;
    };
    defer {
        file.close();
        std.fs.cwd().deleteFile(file_path) catch |err| {
            std.debug.print("Failed to delete file: {}\n", .{err});
        };
    }

    try file.writeAll(&data);

    const bf = try LamaRpreter.Bytefile.parse(&allocator, file_path);
    defer bf.free(&allocator);

    var instructions = try LamaRpreter.run_parse(&allocator, file_path);
    defer instructions.deinit(allocator);

    // BEGIN main
    const begin_instr = LamaRpreter.Instruction{ .BEGIN = .{
        .args = 2,
        .locals = 0,
    } };
    const const_two = LamaRpreter.Instruction{ .CONST = .{
        .index = 2,
    } };
    const const_three = LamaRpreter.Instruction{ .CONST = .{
        .index = 3,
    } };
    const end_instr = LamaRpreter.Instruction.END;

    try std.testing.expectEqual(begin_instr, instructions.items[0]);
    try std.testing.expectEqual(const_two, instructions.items[1]);
    try std.testing.expectEqual(const_three, instructions.items[2]);
    try std.testing.expectEqual(end_instr, instructions.items[11]);
}

// Check evaluating (interpretation) of actual instructions
test "evaluate_binary_op" {
    std.testing.refAllDecls(@This());

    var allocator = std.testing.allocator;

    const file_path = "test1.bc";

    // Will not be used in this test,
    // just for initialization
    const data = [_]u8{
        0x05, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x6d, 0x61, 0x69, 0x6e, 0x00, 0x52, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x10, 0x02, 0x00, 0x00, 0x00, 0x10, 0x03, 0x00, 0x00, 0x00, 0x01, 0x5a, 0x01, 0x00,
        0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x18, 0x5a, 0x02, 0x00, 0x00, 0x00, 0x5a, 0x04, 0x00,
        0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x00, 0x71, 0x16, 0xff,
    };

    // creates if doesnt exist, truncates if it does
    var file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
        std.debug.print("Failed to create file: {}\n", .{err});
        return err;
    };
    defer {
        file.close();
        std.fs.cwd().deleteFile(file_path) catch |err| {
            std.debug.print("Failed to delete file: {}\n", .{err});
        };
    }

    try file.writeAll(&data);

    // Will not be used in this test,
    // just for initialization
    const bf = try LamaRpreter.Bytefile.parse(&allocator, file_path);
    defer bf.free(&allocator);

    const interpreter = try LamaRpreter.Interpreter.new(&allocator, bf, .{ .max_stack_size = 1024 * 1024, .parse_only = false });
    defer interpreter.free(&allocator);

    var results = std.ArrayList(i32).empty;
    defer results.deinit(allocator);

    // Test all 12 operations
    // see `Op` enum in `bytecode.zig`
    for (0..13) |op_index| {
        // clear previous results
        interpreter.operand_stack.clearAndFree(allocator);
        // 2 at top of stack
        const push_const2 = LamaRpreter.Instruction{ .CONST = .{
            .index = 2,
        } };
        try interpreter.eval(push_const2);
        // 3 at top of stack
        const push_const1 = LamaRpreter.Instruction{ .CONST = .{
            .index = 3,
        } };
        try interpreter.eval(push_const1);
        // 3 `op` 2
        const bin_op = LamaRpreter.Instruction{ .BINOP = .{
            .op = @enumFromInt(op_index),
        } };
        try interpreter.eval(bin_op);
        const res = try interpreter.pop();
        try results.append(allocator, res);
    }

    try std.testing.expectEqual(5, results.items[0]); // +
    try std.testing.expectEqual(1, results.items[1]); // -
    try std.testing.expectEqual(6, results.items[2]); // *
    try std.testing.expectEqual(1, results.items[3]); // /
    try std.testing.expectEqual(1, results.items[4]); // %
    try std.testing.expectEqual(0, results.items[5]); // <
    try std.testing.expectEqual(0, results.items[6]); // <=
    try std.testing.expectEqual(1, results.items[7]); // >
    try std.testing.expectEqual(1, results.items[8]); // >=
    try std.testing.expectEqual(0, results.items[9]); // ==
    try std.testing.expectEqual(1, results.items[10]); // !=
    try std.testing.expectEqual(1, results.items[11]); // &&
    try std.testing.expectEqual(1, results.items[12]); // !!

    // TODO: corner cases
}

// Fails with `ERROR: compact_phase: munmap failed`
// nedto somehow workaround gc phases?
// test "evaluate_string_op" {
//     std.testing.refAllDecls(@This());

//     var allocator = std.testing.allocator;

//     const file_path = "test1.bc";

//     const data = [_]u8{
//         0x05, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
//         0x00, 0x00, 0x00, 0x00, 0x6d, 0x61, 0x69, 0x6e, 0x00, 0x52, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
//         0x00, 0x00, 0x10, 0x02, 0x00, 0x00, 0x00, 0x10, 0x03, 0x00, 0x00, 0x00, 0x01, 0x5a, 0x01, 0x00,
//         0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x18, 0x5a, 0x02, 0x00, 0x00, 0x00, 0x5a, 0x04, 0x00,
//         0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x00, 0x71, 0x16, 0xff,
//     };

//     // creates if doesnt exist, truncates if it does
//     var file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
//         std.debug.print("Failed to create file: {}\n", .{err});
//         return err;
//     };
//     defer {
//         file.close();
//         std.fs.cwd().deleteFile(file_path) catch |err| {
//             std.debug.print("Failed to delete file: {}\n", .{err});
//         };
//     }

//     try file.writeAll(&data);

//     const bf = try LamaRpreter.parse(&allocator, file_path);
//     defer {
//         allocator.free(bf.code_section);
//         bf.public_symbols.deinit(allocator);
//         for (bf.string_table.items) |item| {
//             allocator.free(item);
//         }
//         bf.string_table.deinit(allocator);
//         allocator.destroy(bf);
//     }

//     const interpreter = try LamaRpreter.Interpreter.new(&allocator, bf, .{ .max_stack_size = 1024 * 1024, .parse_only = false });
//     defer {
//         interpreter.instructions.deinit(allocator);
//         interpreter.operand_stack.deinit(allocator);
//         allocator.destroy(interpreter);
//     }

//     // var results = std.ArrayList(i32).empty;

//     // "main" pushed to stack (as ref)
//     const push_string = LamaRpreter.Instruction{ .STRING = .{
//         .index = 0,
//     } };
//     try interpreter.eval(push_string);
//     // call "Lstring" to load a string
//     const load_string = LamaRpreter.Instruction{ .CALL = .{
//         .builtin = true,
//         .offset = null,
//         .n = null,
//         .name = .Lstring,
//     } };
//     try interpreter.eval(load_string);

//     const res = try interpreter.pop();
//     const ptr_value: usize = @intCast(res);
//     const ptr: *const []const u8 = @ptrFromInt(ptr_value);
//     const str = ptr.*;
//     // try results.append(allocator, res);

//     try std.testing.expectEqualStrings("main", str);

//     // TODO: array, s-exp, int to string methods
// }
