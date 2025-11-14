const std = @import("std");
const LamaRpreter = @import("LamaRpreter");

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
            std.log.err("Missing file argument\n", .{});
            usage();
            return;
        }
        const file_path = args[2];

        var instructions = try LamaRpreter.run_parse(&gpa, file_path);
        defer instructions.deinit(gpa);

        std.debug.print("Found {d} instructions\n", .{instructions.items.len});

        return;
    } else if (args.len == 2) {
        const file_path = args[1];

        try LamaRpreter.run(&gpa, file_path);
    } else {
        std.log.err("Invalid arguments\n", .{});
        usage();
        return;
    }
}
