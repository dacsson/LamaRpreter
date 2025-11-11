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

    const bf = try LamaRpreter.parse(&allocator, file_path);
    defer {
        allocator.free(bf.code_section);
        bf.public_symbols.deinit(allocator);
        for (bf.string_table.items) |item| {
            allocator.free(item);
        }
        bf.string_table.deinit(allocator);
        allocator.destroy(bf);
    }

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

    const bf = try LamaRpreter.parse(&allocator, file_path);
    defer {
        allocator.free(bf.code_section);
        bf.public_symbols.deinit(allocator);
        for (bf.string_table.items) |item| {
            allocator.free(item);
        }
        bf.string_table.deinit(allocator);
        allocator.destroy(bf);
    }

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
