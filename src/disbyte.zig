//! Dissasembler of Lama bytecode

const std = @import("std");
const bt = @import("bytecode.zig");

// Memory layout of the bytecode file
// +------------------------------------+
// |           File Header              |
// |------------------------------------|
// |  int32: S       | 4 bytes          |
// |  int32: glob_count | 4 bytes       |
// |  int32: P       | 4 bytes          |
// |  P × (int32, int32) | 8 bytes each |
// +------------------------------------+
// |           String Table             |
// |------------------------------------|
// |  S bytes        | Variable         |
// |  e.g., "string1\0string2\0"        |
// +------------------------------------+
// |           Code Region              |
// |------------------------------------|
// |  Variable bytes | Instructions     |
// |  e.g., 0x01 0x02 ... 0xFF          |
// +------------------------------------+

// The unpacked representation of bytecode file
pub const Bytefile = struct {
    stringtab_size: u32,
    global_area_size: u32,
    public_symbols_number: u32,
    public_symbols: std.ArrayList(struct { u32, u32 }),
    string_table: std.ArrayList([]const u8),
    code: std.ArrayList(*bt.Instruction),
};

const BytefileError = error{
    InvalidFileFormat,
    FileReadFailed,
    MemoryAllocationFailed,
    InvalidInstruction,
    UnexpectedEOF,
    NoCodeSection,
};

pub fn parse(allocator: *std.mem.Allocator, fname: []const u8) !*Bytefile {
    const file = try std.fs.cwd().openFile(fname, .{ .mode = .read_only });
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    errdefer allocator.free(buffer);

    var reader = file.reader(buffer);

    const stringtab_size_ = try reader.interface.readAlloc(allocator.*, 4);
    const stringtab_size = std.mem.readInt(u32, stringtab_size_[0..4], .little);
    const global_area_size_ = try reader.interface.readAlloc(allocator.*, 4);
    const global_area_size = std.mem.readInt(u32, global_area_size_[0..4], .little);
    const public_symbols_number_ = try reader.interface.readAlloc(allocator.*, 4);
    const public_symbols_number = std.mem.readInt(u32, public_symbols_number_[0..4], .little);

    // Public symbol table
    // P × (int32, int32) | 8 bytes each
    var public_symbols = std.ArrayList(struct { u32, u32 }).empty;
    for (0..public_symbols_number) |_| {
        const symbol_ = try reader.interface.readAlloc(allocator.*, 4);
        const symbol = std.mem.readInt(u32, symbol_[0..4], .little);

        const name_ = try reader.interface.readAlloc(allocator.*, 4);
        const name = std.mem.readInt(u32, name_[0..4], .little);

        try public_symbols.append(allocator.*, .{ symbol, name });
    }

    // String table
    var string_table = std.ArrayList([]const u8).empty;
    var bytes_read: usize = 0;
    while (bytes_read < stringtab_size) {
        const string = try reader.interface.takeDelimiter(0);
        if (string == null) return BytefileError.UnexpectedEOF;

        try string_table.append(allocator.*, @constCast(string.?));
        bytes_read += if (string.?.len > 0) string.?.len + 1 else 0;
        std.debug.print("Read bytes: {} | {x} bytes\n", .{ bytes_read, string.? });
    }

    // No code section
    if (reader.atEnd()) {
        std.debug.print("[ERROR] Empty code section\n", .{});
        return BytefileError.NoCodeSection;
    }

    var code = std.ArrayList(*bt.Instruction).empty;
    while (!reader.atEnd()) {
        const byte = try reader.interface.readAlloc(allocator.*, 1);
        std.debug.print("Reading instruction: {x}\n", .{byte[0]});
        const instruction = bt.Instruction.from(byte[0]);
        if (instruction == null) {
            return BytefileError.InvalidInstruction;
        }
        std.debug.print("Read instruction: {x} | {}\n", .{ byte[0], instruction.? });
        try code.append(allocator.*, instruction.?);
    }

    const bf = try allocator.create(Bytefile);
    bf.* = Bytefile{
        .stringtab_size = stringtab_size,
        .global_area_size = global_area_size,
        .public_symbols_number = public_symbols_number,
        .public_symbols = public_symbols,
        .string_table = string_table,
        .code = code,
    };
    return bf;
}

pub fn dump(bf: *Bytefile) !void {
    std.debug.print("--------- Bytefile Dump ----------\n", .{});
    std.debug.print("  String Table Size: {d}\n", .{bf.stringtab_size});
    std.debug.print("  Global Area Size: {d}\n", .{bf.global_area_size});
    std.debug.print("  Public Symbols Number: {d}\n", .{bf.public_symbols_number});
    std.debug.print("  Overall instructions: {d}\n", .{bf.code.items.len});

    std.debug.print("  Public Symbols:\n", .{});
    for (bf.public_symbols.items) |symbol| {
        std.debug.print("    Symbol: {}, Name: {}\n", .{ symbol[0], symbol[1] });
    }

    std.debug.print("  String Table:\n", .{});
    for (bf.string_table.items) |string| {
        std.debug.print("    String: {s}\n", .{string});
    }

    std.debug.print("  Code:\n", .{});
    for (bf.code.items) |instruction| {
        std.debug.print("    Instruction: {}\n", .{instruction});
    }
}
