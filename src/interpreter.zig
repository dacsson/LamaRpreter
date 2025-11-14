//! Interpreter for the bytecode instructions.

const std = @import("std");
const bt = @import("bytecode.zig");
const dt = @import("disbyte.zig");

pub extern var __gc_stack_top: c_uint;
pub extern var __gc_stack_bottom: c_uint;

const MAX_STACK_SIZE = 1024 * 1024;

// pub extern fn Lread() c_int;
// pub extern fn Lwrite(c_int) c_int;
pub extern fn Lstring([*c]i64) ?*anyopaque;
pub extern fn Bstring([*c]i64) ?*anyopaque;

const InterpreterError = error{
    StackUnderflow,
    EndOfCodeSection,
    InvalidOpcode,
};

const InterpreterOpts = struct {
    parse_only: bool = false,
    max_stack_size: usize = 1024 * 1024,
};

pub const Interpreter = struct {
    operand_stack: std.ArrayList(i32),
    call_stack: std.ArrayList(i32),
    /// Decoded bytecode file with raw code section
    bf: *dt.Bytefile,
    /// Instruction pointer, moves along code section in `bf`
    ip: usize,
    allocator: *std.mem.Allocator,
    opts: InterpreterOpts,
    /// Collect found instructions, only when `parse_only` is true
    instructions: std.ArrayList(bt.Instruction),

    pub fn new(allocator: *std.mem.Allocator, bf: *dt.Bytefile, opts: InterpreterOpts) !*Interpreter {
        const intr = allocator.create(Interpreter) catch unreachable;
        const operand_stack = std.ArrayList(i32).empty;
        const call_stack = std.ArrayList(i32).empty;

        intr.* = Interpreter{
            .operand_stack = operand_stack,
            .call_stack = call_stack,
            .bf = bf,
            .ip = 0,
            .allocator = allocator,
            .opts = opts,
            .instructions = std.ArrayList(bt.Instruction).empty,
        };
        return intr;
    }

    pub fn free(self: *Interpreter, allocator: *std.mem.Allocator) void {
        self.instructions.deinit(allocator.*);
        self.operand_stack.deinit(allocator.*);
        self.call_stack.deinit(allocator.*);
        allocator.destroy(self);
    }

    pub fn run(self: *Interpreter) !void {
        while (self.ip < self.bf.code_section.len) {
            std.debug.print("Decoding {x}\n", .{self.bf.code_section[self.ip]});
            const encoding = try self.next(u8);
            const instr = try self.decode(encoding);

            if (instr == null) {
                std.debug.print("Instruction: NOP\n", .{});
            } else {
                std.debug.print("Instruction: {}\n", .{instr.?});

                if (self.opts.parse_only) {
                    self.instructions.append(self.allocator.*, instr.?) catch unreachable;
                }
            }
        }
    }

    /// Reads the next n bytes from the code section,
    /// where n is the size of type `T`.
    /// Returns the value read as type `T`, where `T` is an integer type.
    pub fn next(self: *Interpreter, comptime T: type) !T {
        if (self.ip >= self.bf.code_section.len) {
            return error.EndOfCodeSection;
        }

        const bytes = self.bf.code_section[self.ip .. self.ip + @sizeOf(T)];
        self.ip += @sizeOf(T);
        return std.mem.readInt(T, bytes[0..@sizeOf(T)], .little);
    }

    pub fn pop(self: *Interpreter) !i32 {
        const value = self.operand_stack.pop();
        if (value == null) {
            return InterpreterError.StackUnderflow;
        }
        return value.?;
    }

    pub fn push(self: *Interpreter, value: i32) !void {
        try self.operand_stack.append(self.allocator.*, value);
    }

    pub fn eval(self: *Interpreter, instr: bt.Instruction) !void {
        std.debug.print(" -- eval: {}\n", .{instr});
        switch (instr) {
            .NOP => {},
            .BINOP => |bop| {
                const left = try self.pop();
                const right = try self.pop();
                std.debug.print(" -- binop: {} {} {}\n", .{ left, bop.op, right });
                const result = switch (bop.op) {
                    .ADD => left + right,
                    .SUB => left - right,
                    .MUL => left * right,
                    .DIV => @divTrunc(left, right),
                    .MOD => @rem(left, right),
                    .LT => @intFromBool(left < right),
                    .LEQ => @intFromBool(left <= right),
                    .GT => @intFromBool(left > right),
                    .GEQ => @intFromBool(left >= right),
                    .EQ => @intFromBool(left == right),
                    .NEQ => @intFromBool(left != right),
                    .AND => @intFromBool((left != 0) and (right != 0)),
                    .OR => @intFromBool((left != 0) or (right != 0)),
                };
                std.debug.print(" -- result: {}\n", .{result});
                try self.push(result);
            },
            .CONST => |cst| {
                try self.push(cst.index);
            },
            // TODO: test
            .STRING => |str| {
                const str_at = self.bf.string_table.items[@intCast(str.index)];
                var c_str: [*c]u8 = @ptrCast(@alignCast(@constCast(str_at.ptr)));
                c_str[str_at.len] = 0;
                std.debug.print("   -- string: {s} | {x}\n", .{ str_at, str_at });
                std.debug.print("   -- c string: {x}\n", .{c_str});
                // var content: ?*anyopaque = @ptrCast(@alignCast(@constCast(str_at)));
                // std.debug.print("    -- go to Bstring\n", .{});
                const c_str_ptr = &c_str;
                const as_int = @intFromPtr(c_str_ptr);
                var first_arg: i64 = @intCast(as_int);
                const ptr: [*c]i64 = @ptrCast(&first_arg);

                std.debug.print("    -- first_arg: {d} | args: {*}, | as_int: {} | c_str_ptr: {*}\n", .{ first_arg, ptr, as_int, c_str_ptr });

                const build_str: ?*anyopaque = Bstring(ptr);
                std.debug.print("    -- s: {}\n", .{build_str.?});
                const n: c_long = @bitCast(@as(c_ulong, @intFromPtr(build_str.?)));
                // std.debug.print("    -- n: {}\n", .{n});
                try self.push(@intCast(n));
            },
            .CALL => |call| {
                if (call.builtin) {
                    switch (call.name.?) {
                        .Lstring => {
                            const top = try self.pop();
                            const ptr_value: usize = @intCast(top);
                            const ptr_to_str = Lstring(@ptrFromInt(ptr_value));
                            try self.push(@intCast(@intFromPtr(ptr_to_str.?)));
                        },
                        else => unreachable,
                    }
                }
            },
            else => {},
        }
    }

    pub fn decode(self: *Interpreter, encoding: u8) !?bt.Instruction {
        if (encoding == 0xff) return null;

        const opcode = encoding & 0xF0;
        const subopcode = encoding & 0x0F;

        std.debug.print("  Opcode: {x}, Subopcode: {x}\n", .{ opcode, subopcode });

        const instr = switch (opcode) {
            0 => if (subopcode == 0)
                null // NOP
            else
                bt.Instruction{ .BINOP = .{
                    .op = @enumFromInt(subopcode - 1),
                } },
            0x10 => switch (subopcode) {
                0 => bt.Instruction{ .CONST = .{
                    .index = try self.next(i32),
                } },
                0x1 => bt.Instruction{ .STRING = .{
                    .index = try self.next(i32),
                } },
                0x6 => bt.Instruction.END,
                0x8 => bt.Instruction.DROP,
                else => return InterpreterError.InvalidOpcode,
            },
            0x20 => bt.Instruction{ .LOAD = .{
                .index = try self.next(i32),
                .rel = @enumFromInt(subopcode),
            } },
            0x50 => switch (subopcode) {
                2 => bt.Instruction{ .BEGIN = .{
                    .args = try self.next(i32),
                    .locals = try self.next(i32),
                } },
                0xa => bt.Instruction{ .LINE = .{
                    .n = try self.next(i32),
                } },
                else => return InterpreterError.InvalidOpcode,
            },
            0x40 => bt.Instruction{ .STORE = .{
                .index = try self.next(i32),
                .rel = @enumFromInt(subopcode),
            } },
            0x70 => switch (subopcode) {
                0x0 => bt.Instruction{ .CALL = .{
                    .builtin = true,
                    .offset = null,
                    .n = null,
                    .name = .Lread,
                } },
                0x1 => bt.Instruction{ .CALL = .{
                    .builtin = true,
                    .offset = null,
                    .n = null,
                    .name = .Lwrite,
                } },
                0x2 => bt.Instruction{ .CALL = .{
                    .builtin = true,
                    .offset = null,
                    .n = null,
                    .name = .Llength,
                } },
                0x3 => bt.Instruction{ .CALL = .{
                    .builtin = true,
                    .offset = null,
                    .n = null,
                    .name = .Lstring,
                } },
                0x4 => bt.Instruction{ .CALL = .{
                    .builtin = true,
                    .offset = null,
                    .n = try self.next(i32),
                    .name = .Barray,
                } },
                else => return InterpreterError.InvalidOpcode,
            },
            else => return InterpreterError.InvalidOpcode,
        };

        if ((!self.opts.parse_only) and (instr != null)) {
            try self.eval(instr.?);
        }

        return instr;
    }
};
