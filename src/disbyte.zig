//! Dissasembler of Lama bytecode

const std = @import("std");
const bt = @import("bytecode.zig");
const util = @import("util.zig");

const BytefileError = error{
    InvalidFileFormat,
    FileReadFailed,
    MemoryAllocationFailed,
    UnexpectedEOF,
    NoCodeSection,
    InvalidStringIndexInStringTable,
};

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
    string_table: std.ArrayList(u8),
    code_section: []u8, // Kept raw for later interpretation

    pub fn free(self: *Bytefile, allocator: *std.mem.Allocator) void {
        allocator.free(self.code_section);
        self.public_symbols.deinit(allocator.*);
        self.string_table.deinit(allocator.*);
        allocator.destroy(self);
    }

    /// Parse a bytecode file into a Bytefile struct.
    /// Leaves code section raw (as raw bytes) to be interpreted later,
    /// while all other sections are parsed and stored to be easily accessed.
    pub fn parse(allocator: *std.mem.Allocator, fname: []const u8) !*Bytefile {
        const file = try std.fs.cwd().openFile(fname, .{ .mode = .read_only });
        defer file.close();

        const file_size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, file_size);
        defer allocator.free(buffer);

        var reader = file.reader(buffer);

        const stringtab_size_ = try reader.interface.readAlloc(allocator.*, 4);
        defer allocator.free(stringtab_size_);
        const stringtab_size = std.mem.readInt(u32, stringtab_size_[0..4], .little);
        const global_area_size_ = try reader.interface.readAlloc(allocator.*, 4);
        defer allocator.free(global_area_size_);
        const global_area_size = std.mem.readInt(u32, global_area_size_[0..4], .little);
        const public_symbols_number_ = try reader.interface.readAlloc(allocator.*, 4);
        defer allocator.free(public_symbols_number_);
        const public_symbols_number = std.mem.readInt(u32, public_symbols_number_[0..4], .little);

        // Public symbol table
        // P × (int32, int32) | 8 bytes each
        var public_symbols = std.ArrayList(struct { u32, u32 }).empty;

        for (0..public_symbols_number) |_| {
            const symbol_ = try reader.interface.readAlloc(allocator.*, 4);
            defer allocator.free(symbol_);
            const symbol = std.mem.readInt(u32, symbol_[0..4], .little);

            const name_ = try reader.interface.readAlloc(allocator.*, 4);
            defer allocator.free(name_);
            const name = std.mem.readInt(u32, name_[0..4], .little);

            try public_symbols.append(allocator.*, .{ symbol, name });
        }

        // String table
        var string_table = std.ArrayList(u8).empty;
        var bytes_read: usize = 0;
        while (bytes_read < stringtab_size) {
            const string = try reader.interface.takeDelimiter(0);
            if (string == null) return BytefileError.UnexpectedEOF;

            const owned_string = try allocator.dupe(u8, @constCast(string.?));
            try string_table.appendSlice(allocator.*, owned_string);

            // Null terminator
            try string_table.append(allocator.*, 0);

            bytes_read += if (string.?.len > 0) string.?.len + 1 else 0;
        }

        // No code section check
        if (reader.atEnd()) {
            util.dbgs("[ERROR] Empty code section\n", .{});
            return BytefileError.NoCodeSection;
        }

        // Keep code section raw
        var code_section: []u8 = try allocator.alloc(u8, 0);
        var byte: u8 = undefined;
        while (byte != 0xff) {
            const bytes = try reader.interface.readAlloc(allocator.*, 1);
            defer allocator.free(bytes);
            byte = bytes[0];
            code_section = try allocator.realloc(code_section, code_section.len + 1);
            code_section[code_section.len - 1] = byte;
        }

        const bf = try allocator.create(Bytefile);
        bf.* = Bytefile{
            .stringtab_size = stringtab_size,
            .global_area_size = global_area_size,
            .public_symbols_number = public_symbols_number,
            .public_symbols = public_symbols,
            .string_table = string_table,
            .code_section = code_section,
        };
        return bf;
    }

    pub fn get_string_at(self: *Bytefile, index: usize) ![]const u8 {
        std.debug.assert(index < self.string_table.items.len and index >= 0);

        for (index..self.string_table.items.len) |i| {
            if (self.string_table.items[i] == 0) {
                const string = self.string_table.items[index..i];
                return string;
            }
        }

        util.dbgs(" -- string index: {} | string_tab size: {}\n", .{ index, self.string_table.items.len });
        @panic("Invalid string index in string table");
        // return BytefileError.InvalidStringIndexInStringTable;
    }

    pub fn dump(self: *Bytefile) !void {
        util.dbgs("--------- Bytefile Dump ----------\n", .{});
        util.dbgs("  String Table Size: {d}\n", .{self.stringtab_size});
        util.dbgs("  Global Area Size: {d}\n", .{self.global_area_size});
        util.dbgs("  Public Symbols Number: {d}\n", .{self.public_symbols_number});
        util.dbgs("  Overall code section bytes: {d}\n", .{self.code_section.len});

        util.dbgs("  Public Symbols:\n", .{});
        for (self.public_symbols.items) |symbol| {
            util.dbgs("    Symbol: {}, Name: {}\n", .{ symbol[0], symbol[1] });
        }

        util.dbgs("  String Table:\n", .{});
        util.dbgs("    String: {s}\n", .{self.string_table.items});

        util.dbgs("  Code:\n", .{});
        for (self.code_section) |instruction| {
            util.dbgs("    Opcode: {}\n", .{instruction});
        }
    }
};
