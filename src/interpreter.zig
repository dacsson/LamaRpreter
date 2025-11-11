//! Interpreter for the bytecode instructions.

const std = @import("std");
const bt = @import("bytecode.zig");
const dt = @import("disbyte.zig");
const runtime = @cImport({
    @cInclude("runtime.h");
});

pub extern var __gc_stack_top: c_uint;
pub extern var __gc_stack_bottom: c_uint;

const MAX_STACK_SIZE = 1024 * 1024;

pub extern fn Lread() c_int;
pub extern fn Lwrite(c_int) c_int;

const InterpreterError = error{
    StackUnderflow,
    EndOfCodeSection,
    InvalidOpcode,
};

pub const Interpreter = struct {
    operand_stack: std.ArrayList(u64),
    bf: *dt.Bytefile,
    ip: usize,
    allocator: *std.mem.Allocator,

    pub fn new(allocator: *std.mem.Allocator, bf: *dt.Bytefile) !*Interpreter {
        const intr = allocator.create(Interpreter) catch unreachable;
        const operand_stack = std.ArrayList(u64).empty;
        // try operand_stack.append(allocator.*, 0); // fake argc
        // try operand_stack.append(allocator.*, 0); // fake argv
        // try operand_stack.append(allocator.*, 2);

        intr.* = Interpreter{
            .operand_stack = operand_stack,
            .bf = bf,
            .ip = 0,
            .allocator = allocator,
        };
        return intr;
    }

    pub fn run(self: *Interpreter) !void {
        while (self.ip < self.bf.code_section.len) {
            std.debug.print("Decoding {x}\n", .{self.bf.code_section[self.ip]});
            const encoding = try self.next(u8);
            const instr = try self.decode(encoding);
            // self.ip += 1; // 1 byte for instruction encoding
            if (instr == null) {
                std.debug.print("Instruction: NOP\n", .{});
            } else {
                std.debug.print("Instruction: {}\n", .{instr.?});
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

    pub fn pop(self: *Interpreter) !u64 {
        const value = self.operand_stack.pop();
        if (value == null) {
            return InterpreterError.StackUnderflow;
        }
        return value;
    }

    pub fn push(self: *Interpreter, value: u64) !void {
        try self.operand_stack.append(self.allocator.*, value);
    }

    // pub fn decode(byte: u8) type {
    //     const opcode = encoding & 0xF0;
    //     const subopcode = encoding & 0x0F;
    // }

    // fn eval_binop(op: BinOp) !void {
    //     const left = try self.stack_pop();
    //     const right = try self.stack_pop();
    //     const result = switch (op) {
    //         .ADD => left + right,
    //         .SUB => left - right,
    //         .MUL => left * right,
    //         .DIV => left / right,
    //         .MOD => left % right,
    //     };
    //     try self.stack_push(result);
    // }

    pub fn decode(self: *Interpreter, encoding: u8) !?bt.Instruction {
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

                else => null,
            },
            0x50 => switch (subopcode) {
                2 => bt.Instruction{ .BEGIN = .{
                    .args = try self.next(i32),
                    .locals = try self.next(i32),
                } },

                else => null,
            },
            else => return InterpreterError.InvalidOpcode,
        };
        return instr;
    }
};
