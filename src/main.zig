const std = @import("std");
const LamaRpreter = @import("LamaRpreter");
const runtime = @cImport({
    @cInclude("runtime.h");
});

pub fn usage() void {
    std.debug.print("Usage: LamaRpreter <flags> <file>.bc\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  --parse-only    Parse the file but do not execute it\n", .{});
    std.debug.print("  --help          Display this help message\n", .{});
}

pub fn main() !void {
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    var gpa = general_purpose_allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len == 1) {
        usage();
        std.debug.print("\nNo file specified\n", .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "--help")) {
        usage();
        return;
    }

    if (std.mem.eql(u8, args[1], "--parse-only")) {
        if (args.len != 3) {
            usage();
            std.debug.print("\nMissing file argument\n", .{});
            return;
        }
        const file_path = args[2];
        const bf = try LamaRpreter.parse(&gpa, file_path);
        try LamaRpreter.dump(bf);
        return;
    }
}

test "parse" {
    std.testing.refAllDecls(@This());

    var allocator = std.testing.allocator;

    const file_path = "/home/safonoff/Uni/VirtualMachines/LamaRpreter/dump/test1.bc";

    std.debug.print("File location: {s}.\n", .{file_path});

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

    try std.testing.expect(std.mem.eql(u8, "main", bf.string_table.items[0]));
    try std.testing.expectEqual(@as(usize, 49), bf.code_section.len);
}
