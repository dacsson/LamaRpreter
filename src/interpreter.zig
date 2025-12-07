//! Interpreter for the bytecode instructions.

const std = @import("std");
const bt = @import("bytecode.zig");
const dt = @import("disbyte.zig");
const util = @import("util.zig");

pub extern var __gc_stack_top: c_ulong;
pub extern var __gc_stack_bottom: c_ulong;

const MAX_STACK_SIZE = 1024 * 1024;

// pub extern fn Lread() c_int;
// pub extern fn Lwrite(c_int) c_int;
pub extern fn Lstring([*c]i64) ?*anyopaque;
pub extern fn Bstring([*c]i64) ?*anyopaque;
pub extern fn Lwrite(c_long) c_long;

const InterpreterError = error{
    StackUnderflow,
    EndOfCodeSection,
    InvalidOpcode,
};

const InterpreterOpts = struct {
    parse_only: bool = false,
    max_stack_size: usize = 1024 * 1024,
};

const FrameMetadata = struct {
    n_locals: i32,
    n_args: i32,
    ret_frame_pointer: usize,
    ret_ip: usize,
};

pub const Interpreter = struct {
    operand_stack: std.ArrayList(i32),
    frame_pointer: usize,
    /// Decoded bytecode file with raw code section
    bf: *dt.Bytefile,
    /// Instruction pointer, moves along code section in `bf`
    ip: usize,
    allocator: *std.mem.Allocator,
    opts: InterpreterOpts,
    /// Collect found instructions, only when `parse_only` is true
    instructions: std.ArrayList(bt.Instruction),
    /// Global variables
    globals: std.ArrayList(i32),

    pub fn new(allocator: *std.mem.Allocator, bf: *dt.Bytefile, opts: InterpreterOpts) !*Interpreter {
        const intr = allocator.create(Interpreter) catch unreachable;
        var operand_stack = try std.ArrayList(i32).initCapacity(allocator.*, 1024);

        // ... <- frame points to this index
        // ARGS_COUNT
        // LOCALS_COUNT
        // OLD_FRAME_POINTER
        // OLD_IP
        // ARG1
        // ARG2
        // ...
        // ARGN
        // LOCAL1
        // LOCAL2
        // ...
        // LOCALN
        try operand_stack.append(allocator.*, 0); // FRAME_PTR
        try operand_stack.append(allocator.*, 2); // ARGS_COUNT
        try operand_stack.append(allocator.*, 0); // LOCALS_COUNT
        try operand_stack.append(allocator.*, 0); // OLD_FRAME_POINTER
        try operand_stack.append(allocator.*, 0); // OLD_IP
        try operand_stack.append(allocator.*, 0); // ARGV
        try operand_stack.append(allocator.*, 0); // ARGC
        // 0 locals

        intr.* = Interpreter{
            .operand_stack = operand_stack,
            .frame_pointer = 0,
            .bf = bf,
            .ip = 0,
            .allocator = allocator,
            .opts = opts,
            .instructions = std.ArrayList(bt.Instruction).empty,
            .globals = std.ArrayList(i32).empty,
        };

        __gc_stack_bottom = 0;
        __gc_stack_top = __gc_stack_bottom;

        return intr;
    }

    pub fn free(self: *Interpreter, allocator: *std.mem.Allocator) void {
        self.instructions.deinit(allocator.*);
        self.operand_stack.deinit(allocator.*);
        self.globals.deinit(allocator.*);
        allocator.destroy(self);
    }

    /// Main interpreter loop
    pub fn run(self: *Interpreter) !void {
        while (self.ip < self.bf.code_section.len) {
            util.dbgs("Decoding {x} | current ip: {d}\n", .{ self.bf.code_section[self.ip], self.ip });
            const encoding = try self.next(u8);
            const instr = try self.decode(encoding);

            if (instr == null) {
                util.dbgs("Instruction: NOP\n", .{});
            } else {
                // util.dbgs("Instruction: {}\n", .{instr.?});

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
        // A generic constraint - note that this is a compile time
        // check, will not result in a runtime error
        if (comptime !(@typeInfo(T) == .int)) {
            return error.InvalidType;
        }

        if (self.ip >= self.bf.code_section.len) {
            return error.EndOfCodeSection;
        }

        const bytes = self.bf.code_section[self.ip .. self.ip + @sizeOf(T)];
        self.ip += @sizeOf(T);
        return std.mem.readInt(T, bytes[0..@sizeOf(T)], .little);
    }

    /// Pop from the operand stack
    pub fn pop(self: *Interpreter) !i32 {
        // const value = try util.pop_head(&self.operand_stack);
        const value = self.operand_stack.pop() orelse {
            return InterpreterError.StackUnderflow;
        };
        util.dbgs("POP: {d}\n", .{value});
        if (self.operand_stack.items.len > 0) {
            __gc_stack_top = @intCast(@intFromPtr(self.operand_stack.items.ptr + self.operand_stack.items.len - 1));
        } else {
            __gc_stack_top = __gc_stack_bottom; // or 0?
        }

        util.dbgs("----- STACK (POP) ----\n", .{});
        for (0..self.operand_stack.items.len) |i| {
            if (i == self.frame_pointer) {
                util.dbgs("  [{}] {} <- frame pointer\n", .{ i, self.operand_stack.items[i] });
            } else if (i == self.frame_pointer + 1) {
                util.dbgs("  [{}] {} <- argn\n", .{ i, self.operand_stack.items[i] });
            } else if (i == self.frame_pointer + 2) {
                util.dbgs("  [{}] {} <- localn\n", .{ i, self.operand_stack.items[i] });
            } else if (i == self.frame_pointer + 3) {
                util.dbgs("  [{}] {} <- old frame pointer\n", .{ i, self.operand_stack.items[i] });
            } else if (i == self.frame_pointer + 4) {
                util.dbgs("  [{}] {} <- return ip\n", .{ i, self.operand_stack.items[i] });
            } else {
                util.dbgs("  [{}] {}\n", .{ i, self.operand_stack.items[i] });
            }
        }
        util.dbgs("----- STACK (POP) ----\n", .{});

        return value;
    }

    /// Push to the operand stack
    pub fn push(self: *Interpreter, value: i32) !void {
        // try util.prepend(&self.operand_stack, self.allocator, value);
        try self.operand_stack.append(self.allocator.*, value);
        __gc_stack_top = @intCast(@intFromPtr(self.operand_stack.items.ptr + self.operand_stack.items.len - 1));

        util.dbgs("----- STACK (PUSH) ----\n", .{});
        for (0..self.operand_stack.items.len) |i| {
            if (i == self.frame_pointer) {
                util.dbgs("  [{}] {} <- frame pointer\n", .{ i, self.operand_stack.items[i] });
            } else if (i == self.frame_pointer + 1) {
                util.dbgs("  [{}] {} <- argn\n", .{ i, self.operand_stack.items[i] });
            } else if (i == self.frame_pointer + 2) {
                util.dbgs("  [{}] {} <- localn\n", .{ i, self.operand_stack.items[i] });
            } else if (i == self.frame_pointer + 3) {
                util.dbgs("  [{}] {} <- old frame pointer\n", .{ i, self.operand_stack.items[i] });
            } else if (i == self.frame_pointer + 4) {
                util.dbgs("  [{}] {} <- return ip\n", .{ i, self.operand_stack.items[i] });
            } else {
                util.dbgs("  [{}] {}\n", .{ i, self.operand_stack.items[i] });
            }
        }
        util.dbgs("----- STACK (PUSH) ----\n", .{});
        // std.debug.assert(__gc_stack_top >= @frameAddress());
    }

    fn get_frame_metadata(self: *Interpreter) !FrameMetadata {
        const n_locals = self.operand_stack.items[self.frame_pointer + 2];
        const n_args = self.operand_stack.items[self.frame_pointer + 1];
        const ret_frame_pointer = self.operand_stack.items[self.frame_pointer + 3];
        const ret_ip = self.operand_stack.items[self.frame_pointer + 4];

        return FrameMetadata{
            .n_locals = n_locals,
            .n_args = n_args,
            .ret_frame_pointer = @intCast(ret_frame_pointer),
            .ret_ip = @intCast(ret_ip),
        };
    }

    /// Evaluate a decoded instruction
    pub fn eval(self: *Interpreter, instr: bt.Instruction) !void {
        util.dbgs(" -- eval: {}\n", .{instr});
        switch (instr) {
            .NOP => {},
            .BINOP => |bop| {
                const left = try self.pop();
                const right = try self.pop();
                util.dbgs(" -- binop: {} {} {}\n", .{ left, bop.op, right });
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
                util.dbgs(" -- result: {}\n", .{result});
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
                util.dbgs("   -- string: {s} | {x}\n", .{ str_at, str_at });
                util.dbgs("   -- c string: {x}\n", .{c_str});
                // var content: ?*anyopaque = @ptrCast(@alignCast(@constCast(str_at)));
                // util.dbgs("    -- go to Bstring\n", .{});
                const c_str_ptr = &c_str;
                const as_int = @intFromPtr(c_str_ptr);
                var first_arg: i64 = @intCast(as_int);
                const ptr: [*c]i64 = @ptrCast(&first_arg);

                util.dbgs("    -- first_arg: {d} | args: {*}, | as_int: {} | c_str_ptr: {*}\n", .{ first_arg, ptr, as_int, c_str_ptr });
                util.dbgs("    builtinFrame: {} vs gc_top: {} vs gc_bottom: {}\n", .{ @frameAddress(), __gc_stack_top, __gc_stack_bottom });

                const build_str: ?*anyopaque = Bstring(ptr);
                util.dbgs("    -- s: {}\n", .{build_str.?});
                const n: c_long = @bitCast(@as(c_ulong, @intFromPtr(build_str.?)));
                // util.dbgs("    -- n: {}\n", .{n});
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
                        .Lwrite => {
                            const val = try self.pop();
                            const as_long: c_long = @intCast(val);
                            _ = Lwrite(util.BOX(as_long));
                            try self.push(val);
                        },
                        else => unreachable,
                    }
                }
            },
            .BEGIN => |begin| {
                const old_frame_pointer = self.frame_pointer;
                // Set frame pointer as index into OS
                self.frame_pointer = self.operand_stack.items.len - 1;

                for (0..@intCast(begin.locals)) |_| {
                    _ = try self.push(0);
                }

                // Push arg and locals count
                try self.push(begin.args);
                try self.push(begin.locals);

                // Where to return in sack operands
                // to after the function call
                try self.push(@intCast(old_frame_pointer));

                // Where to return in the bytecode after this call
                util.dbgs("current ip: {d}\n", .{self.ip});
                try self.push(@intCast(self.ip));

                // TODO: begin.arguments handler
                //       handled by the CALL instruction

                util.dbgs("Calling begin with {d} locals and {d} arguments\n", .{ begin.locals, begin.args });

                // After this call in OS:
                // ... <- frame points to this index
                // ARGS_COUNT
                // LOCALS_COUNT
                // OLD_FRAME_POINTER
                // OLD_IP
                // ARG1
                // ARG2
                // ...
                // ARGN
                // LOCAL1
                // LOCAL2
                // ...
                // LOCALN
            },
            .END => {
                // At this point we have:
                // ... <- frame points to this index
                // ARGS_COUNT
                // LOCALS_COUNT
                // OLD_FRAME_POINTER
                // OLD_IP
                // ARG1
                // ARG2
                // ...
                // ARGN
                // LOCAL1
                // LOCAL2
                // ...
                // LOCALN
                // RET_VALUE
                const return_value = try self.pop();

                const frame_metadata = try self.get_frame_metadata();
                util.dbgs("Frame metadata: {}", .{frame_metadata});
                self.frame_pointer = frame_metadata.ret_frame_pointer;
                self.ip =
                    if (self.frame_pointer != 0)
                        frame_metadata.ret_ip
                    else
                        self.ip;

                // Pop return ip
                _ = try self.pop();

                // Pop old_frame_pointer
                _ = try self.pop();

                // Pop local count
                _ = try self.pop();

                // Pop args count
                _ = try self.pop();

                for (0..@intCast(frame_metadata.n_args)) |_| {
                    _ = try self.pop();
                }

                for (0..@intCast(frame_metadata.n_locals)) |_| {
                    _ = try self.pop();
                }

                // Now stack should be back to the state before the call

                // Push return value
                try self.push(return_value);
            },
            .STORE => |store| {
                switch (store.rel) {
                    .G => {
                        try self.globals.append(self.allocator.*, self.operand_stack.getLast());
                        util.dbgs("Stored global {d} with value {d}: {d}\n", .{ store.index, self.operand_stack.items[0], self.globals.items[@intCast(store.index)] });
                    },
                    else => unreachable,
                }
            },
            .DROP => {
                _ = try self.pop();
            },
            .LOAD => |load| {
                switch (load.rel) {
                    .G => {
                        try self.push(self.globals.items[@intCast(load.index)]);
                    },
                    else => unreachable,
                }
            },
            .LINE => |line| {
                util.dbgs("Line: {}\n", .{line.n});
            },
            // else => unreachable,
        }
    }

    /// Decode a byte into an instruction
    pub fn decode(self: *Interpreter, encoding: u8) !?bt.Instruction {
        if (encoding == 0xff) return null;

        const opcode = encoding & 0xF0;
        const subopcode = encoding & 0x0F;

        // util.dbgs("  Opcode: {x}, Subopcode: {x}\n", .{ opcode, subopcode });

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

        // When constructed we can now evaluate the instruction
        if ((!self.opts.parse_only) and (instr != null)) {
            try self.eval(instr.?);
        }

        return instr;
    }
};
