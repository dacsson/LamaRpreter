//! Interpreter for the bytecode instructions.

const std = @import("std");

const bt = @import("bytecode.zig");
const dt = @import("disbyte.zig");
const Object = @import("object.zig").Object;
const util = @import("util.zig");
const rcommon = @cImport({
    @cInclude("runtime_common.h");
});
const gc = @cImport({
    @cInclude("gc.h");
});

pub extern var __gc_stack_top: c_ulong align(16);
pub extern var __gc_stack_bottom: c_ulong align(16);
pub extern fn __init() void;
pub extern fn __gc_init() void;
pub extern fn __shutdown() void;

const MAX_STACK_SIZE = 1024 * 1024;

pub extern fn Lstring([*c]i64) ?*anyopaque;
pub extern fn Bstring([*c]i64) ?*anyopaque;
pub extern fn Lwrite(c_long) c_long;
pub extern fn Lread() c_long;
pub extern fn Llength(c_long) c_long;
pub extern fn Barray([*c]i64, i64) ?*anyopaque;

const InterpreterError = error{
    StackUnderflow,
    EndOfCodeSection,
    InvalidOpcode,
    InvalidType,
    OutOfBoundsAccess,
};

const InterpreterOpts = struct {
    parse_only: bool = false,
    max_stack_size: usize = 1024 * 1024,
};

/// Frame metadata for the interpreter.
/// Because we have only one stack, we keep index
/// of the frame pointer.
const FrameMetadata = struct {
    n_locals: i64,
    n_args: i64,
    ret_frame_pointer: usize,
    ret_ip: usize,
};

pub const Interpreter = struct {
    operand_stack: std.ArrayList(Object),
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
    globals: std.ArrayList(Object),

    pub fn new(allocator: *std.mem.Allocator, bf: *dt.Bytefile, opts: InterpreterOpts) !*Interpreter {
        const intr = allocator.create(Interpreter) catch unreachable;
        var operand_stack = try std.ArrayList(Object).initCapacity(allocator.*, MAX_STACK_SIZE);

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

        // Emulating call to main
        try operand_stack.append(allocator.*, Object.from_int(0)); // FRAME_PTR
        try operand_stack.append(allocator.*, Object.from_int(2)); // ARGS_COUNT
        try operand_stack.append(allocator.*, Object.from_int(0)); // LOCALS_COUNT
        try operand_stack.append(allocator.*, Object.from_int(0)); // OLD_FRAME_POINTER
        try operand_stack.append(allocator.*, Object.from_int(0)); // OLD_IP
        try operand_stack.append(allocator.*, Object.from_int(0)); // ARGV
        try operand_stack.append(allocator.*, Object.from_int(0)); // ARGC
        try operand_stack.append(allocator.*, Object.from_int(0)); // CURR_IP
        // 0 locals

        intr.* = Interpreter{
            .operand_stack = operand_stack,
            .frame_pointer = 0,
            .bf = bf,
            .ip = 0,
            .allocator = allocator,
            .opts = opts,
            .instructions = std.ArrayList(bt.Instruction).empty,
            .globals = std.ArrayList(Object).empty,
        };

        // Init GC
        __init();

        // Sync GC stack pointers
        intr.sync_gc_stack();

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
                if (self.opts.parse_only) {
                    self.instructions.append(self.allocator.*, instr.?) catch unreachable;
                } else {
                    // When constructed we can now evaluate the instruction
                    try self.eval(instr.?);
                }

                // HACK: if we encounter END instruction, while in frame 0
                //       (a.k.a main function) we exit the interpreter
                if (instr.? == .END and self.frame_pointer == 0) {
                    break;
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

    // TODO: fails at this line in runtime.c:19 gc check:
    //       `assert(__builtin_frame_address(0) <= (void *)__gc_stack_top)`
    //       commented out this in runtime for now
    fn sync_gc_stack(self: *Interpreter) void {
        const items = self.operand_stack.items;

        if (items.len == 0) {
            __gc_stack_bottom = 0;
            __gc_stack_top = 0;
            return;
        }

        // compute bottom as the start of current frame:
        const frame_idx: usize = @intCast(self.frame_pointer);
        // clamp frame_idx to valid range
        const bottom_idx = if (frame_idx <= items.len) frame_idx else items.len;

        const bottom_ptr = items.ptr + bottom_idx;

        // compute top - if empty or frame_idx == items.len then top <= bottom
        if (items.len == 0 or bottom_idx == items.len) {
            __gc_stack_bottom = @as(c_ulong, @intFromPtr(bottom_ptr));
            __gc_stack_top = __gc_stack_bottom; // empty region or no live roots in frame
        } else {
            const top_ptr = items.ptr + (items.len - 1);
            __gc_stack_bottom = @as(c_ulong, @intFromPtr(bottom_ptr));
            __gc_stack_top = @as(c_ulong, @intFromPtr(top_ptr));
        }
    }

    /// Pop from the operand stack
    pub fn pop(self: *Interpreter) !Object {
        // const value = try util.pop_head(&self.operand_stack);
        const value = self.operand_stack.pop() orelse {
            return InterpreterError.StackUnderflow;
        };
        util.dbgs("POP: {}\n", .{value});
        self.sync_gc_stack();
        // __gc_stack_top = @intCast(@intFromPtr(&self.operand_stack.getLast()));
        // __gc_stack_top = @intCast(@intFromPtr(__gc_stack_bottom - @as(c_ulong, @sizeOf(i32))));
        // if (self.operand_stack.items.len > 0) {
        //     __gc_stack_top = @intCast(@intFromPtr(self.operand_stack.items.ptr + self.operand_stack.items.len - 1));
        // } else {
        //     __gc_stack_top = __gc_stack_bottom; // or 0?
        // }

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
    pub fn push(self: *Interpreter, value: Object) !void {
        // try util.prepend(&self.operand_stack, self.allocator, value);
        try self.operand_stack.append(self.allocator.*, value);
        // __gc_stack_top = @intCast(@intFromPtr(__gc_stack_bottom + @as(c_ulong, @sizeOf(i32))));
        // __gc_stack_top = @intCast(@intFromPtr(&self.operand_stack.getLast()));
        self.sync_gc_stack();

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
            .n_locals = n_locals.data,
            .n_args = n_args.data,
            .ret_frame_pointer = @intCast(ret_frame_pointer.data),
            .ret_ip = @intCast(ret_ip.data),
        };
    }

    /// Get the argument at the given index in the current frame.
    fn get_argument(self: *Interpreter, index: usize) ?Object {
        const metadata = try self.get_frame_metadata();
        if (metadata.n_args == 0) return null;

        const arg = self.operand_stack.items[self.frame_pointer + 5 + index];
        return arg;
    }

    fn set_argument(self: *Interpreter, index: usize, value: Object) !void {
        const metadata = try self.get_frame_metadata();
        if (metadata.n_args == 0) return;

        self.operand_stack.items[self.frame_pointer + 5 + index] = value;
    }

    /// Get the local variable at the given index in the current frame.
    fn get_local(self: *Interpreter, index: usize) ?Object {
        const metadata = try self.get_frame_metadata();
        if (metadata.n_locals == 0) return null;

        const n_args: usize = @intCast(metadata.n_args);
        const local = self.operand_stack.items[self.frame_pointer + 5 + n_args + index];
        return local;
    }

    /// Set the local variable at the given index in the current frame.
    fn set_local(self: *Interpreter, index: usize, value: Object) !void {
        const metadata = try self.get_frame_metadata();
        if (metadata.n_locals == 0) return;

        const n_args: usize = @intCast(metadata.n_args);
        self.operand_stack.items[self.frame_pointer + 5 + n_args + index] = value;
    }

    /// Evaluate a decoded instruction
    pub fn eval(self: *Interpreter, instr: bt.Instruction) !void {
        util.dbgs(" -- eval: {}\n", .{instr});
        switch (instr) {
            .NOP => {},
            .BINOP => |bop| {
                // PRESEDENCE!!!
                const right = try self.pop();
                const left = try self.pop();
                util.dbgs(" -- binop: {} {} {}\n", .{ left, bop.op, right });
                const result = switch (bop.op) {
                    .ADD => left.data + right.data,
                    .SUB => left.data - right.data,
                    .MUL => left.data * right.data,
                    .DIV => @divTrunc(left.data, right.data),
                    .MOD => @rem(left.data, right.data),
                    .LT => @intFromBool(left.data < right.data),
                    .LEQ => @intFromBool(left.data <= right.data),
                    .GT => @intFromBool(left.data > right.data),
                    .GEQ => @intFromBool(left.data >= right.data),
                    .EQ => @intFromBool(left.data == right.data),
                    .NEQ => @intFromBool(left.data != right.data),
                    .AND => @intFromBool((left.data != 0) and (right.data != 0)),
                    .OR => @intFromBool((left.data != 0) or (right.data != 0)),
                };
                util.dbgs(" -- result: {}\n", .{result});
                try self.push(Object.from_int(result));
            },
            .CONST => |cst| {
                try self.push(Object.from_int(cst.index));
            },
            // TODO: test
            .STRING => |str| {
                const str_at = self.bf.string_table.items[@intCast(str.index)];
                // var value = Object.from_string(str_at);
                // const ptr: [*c]i64 = @ptrCast(&value.data);

                // // util.dbgs("    -- first_arg: {d} | args: {*}, | as_int: {} | c_str_ptr: {*}\n", .{ first_arg, ptr, as_int, c_str_ptr });
                // util.dbgs("    builtinFrame: {} vs gc_top: {} vs gc_bottom: {}\n", .{ @frameAddress(), __gc_stack_top, __gc_stack_bottom });

                // const build_str: ?*anyopaque = Bstring(ptr);
                // util.dbgs("    -- s: {}\n", .{build_str.?});
                // const n: c_long = @bitCast(@as(c_ulong, @intFromPtr(build_str.?)));
                // // util.dbgs("    -- n: {}\n", .{n});
                // const top: c_long = @intCast(@intFromPtr(str_at.ptr));

                // // util.dbgs("Boxing value {d} -> {d} {d}\n", .{ top.data, top.BOX(), rcommon.BOX(top.data) });
                // var boxed = Object.from_int(top);
                // util.dbgs("Boxing value: {d} -> {d} | {d}\n", .{ top, boxed.box().data, rcommon.BOX(@intFromPtr(str_at.ptr)) });
                // if (rcommon.UNBOXED(rcommon.BOX(@intFromPtr(str_at.ptr))) == 1) {
                //     @panic("Unboxed value");
                // }
                // try self.push(boxed.box());
                const alloc_str = gc.alloc_string(str_at.len);
                const content_ptr = gc.get_object_content_ptr(alloc_str).?;

                const to_data = util.TO_DATA(content_ptr);
                const contents: [*c]u8 = util.contents(to_data);

                @memcpy(contents, str_at);

                contents[str_at.len] = 0;

                util.dbgs("Content string is: {s}\n", .{contents});

                try self.push(Object.from_ptr(contents));
            },
            .CALL => |call| {
                if (call.builtin) {
                    switch (call.name.?) {
                        .Lstring => {
                            var top = try self.pop();

                            var as_str = try top.to_string(self.allocator.*);

                            const alloc_str = gc.alloc_string(as_str.len);
                            const content_ptr = gc.get_object_content_ptr(alloc_str).?;

                            const to_data = util.TO_DATA(content_ptr);
                            const contents: [*c]u8 = util.contents(to_data);

                            @memcpy(contents, as_str);

                            try self.push(Object.from_ptr(contents));
                            // if (top.is_aggregate()) {
                            //     const ptr_value: usize = @intCast(top.data);
                            //     const ptr_to_str = Lstring(@ptrFromInt(ptr_value));
                            //     try self.push(Object.from_int(@intCast(@intFromPtr(ptr_to_str.?))));
                            // } else {
                            //     const one_array: [*c]i64 = @ptrCast(&top.data);
                            //     const ptr_to_str = Lstring(one_array);
                            //     try self.push(Object.from_int(@intCast(@intFromPtr(ptr_to_str.?))));
                            // }
                        },
                        .Lwrite => {
                            const val = try self.pop();
                            const as_long: c_long = @intCast(val.data);
                            _ = Lwrite(util.BOX(as_long));
                            try self.push(val);
                        },
                        .Lread => {
                            const val = Lread();
                            var boxed = Object.from_int(val);
                            try self.push(boxed.unbox());
                        },
                        .Llength => {
                            const val = try self.pop();
                            // const as_long: c_long = @intCast(val.data);
                            const len = Llength(val.data);
                            // const as_str = @ptrFromInt(val);
                            // util.dbgs("Content: {s}", )
                            var boxed = Object.from_int(len);
                            try self.push(boxed.unbox());
                        },
                        .Barray => {
                            const len: usize = @intCast(call.n.?);

                            var elements = try std.ArrayList(i64).initCapacity(self.allocator.*, len);
                            defer elements.deinit(self.allocator.*);

                            for (0..len) |_| {
                                const element = try self.pop();
                                try elements.append(self.allocator.*, element.data);
                            }

                            // Reverse, due to stack precedence
                            var reversed = try std.ArrayList(i64).initCapacity(self.allocator.*, len);
                            defer reversed.deinit(self.allocator.*);

                            for (0..len) |_| {
                                try reversed.append(self.allocator.*, elements.pop().?);
                            }

                            const len_64: i64 = @intCast(len);

                            const array = Barray(reversed.items.ptr, rcommon.BOX(len_64)).?;

                            try self.push(Object.from_ptr(array));
                        },
                        // else => unreachable,
                    }
                } else {
                    // Push old instruction pointer
                    // `begin` instruction will collect it
                    try self.push(Object.from_int(@intCast(self.ip)));

                    // Set new ip
                    const offset = call.offset orelse {
                        @panic("Not-builtin call without offset specified\n");
                    };
                    self.ip = @intCast(offset);

                    util.dbgs("ip at {d} {}", .{ self.ip, self.bf.code_section[self.ip] });

                    // // Take number of arguments
                    // const n_args = call.n orelse {
                    //     @panic("Not-builtin call without number of arguments specified\n");
                    // };

                    // // Push n_args (begin will rearrange them)
                    // try self.push(Object.from_int(n_args));
                }
            },
            .BEGIN => |begin| {
                // // Take number of arguments pushed by `call`
                // const n_args = try self.pop();
                const old_ip = try self.pop();

                // Collect arguments from previous frame
                var arguments = std.ArrayList(Object).empty;
                defer arguments.deinit(self.allocator.*);

                for (0..@intCast(begin.args)) |_| {
                    const arg = try self.pop();
                    try arguments.append(self.allocator.*, arg);
                }

                const old_frame_pointer = self.frame_pointer;
                // Set new frame pointer as index into OS
                self.frame_pointer = self.operand_stack.items.len - 1;

                // Push arg and locals count
                try self.push(Object.from_int(begin.args));
                try self.push(Object.from_int(begin.locals));

                // Where to return in sack operands
                // to after the function call
                try self.push(Object.from_int(@intCast(old_frame_pointer)));

                // Where to return in the bytecode after this call
                // util.dbgs("current ip: {d}\n", .{self.ip});
                try self.push(old_ip);

                // Push arguments
                for (0..@intCast(begin.args)) |_| {
                    _ = try self.push(arguments.pop().?);
                }

                // Initialize locals with 0
                for (0..@intCast(begin.locals)) |_| {
                    _ = try self.push(Object.from_int(0));
                }

                // TODO: begin.arguments handler
                //       handled by the CALL instruction

                // Synchronize with the garbage collector we replace
                // bottom as the start of this frames operand stack section
                // __gc_stack_bottom = @intCast(@intFromPtr(&self.operand_stack.getLast()));
                self.sync_gc_stack();

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
                        if (store.index < 0) {
                            return InterpreterError.OutOfBoundsAccess;
                        }

                        if (store.index >= self.globals.items.len) {
                            try self.globals.append(self.allocator.*, self.operand_stack.getLast());
                        } else {
                            self.globals.items[@intCast(store.index)] = self.operand_stack.getLast();
                        }

                        util.dbgs("Stored global {d} with value {}: {}\n", .{ store.index, self.operand_stack.items[0], self.globals.items[@intCast(store.index)] });
                    },
                    .L => {
                        try self.set_local(@intCast(store.index), self.operand_stack.getLast());
                        // util.dbgs("Stored local {d} with value {}: {}\n", .{ store.index, self.operand_stack.items[0], self.locals.items[@intCast(store.index)] });
                    },
                    .A => {
                        try self.set_argument(@intCast(store.index), self.operand_stack.getLast());
                        // util.dbgs("Stored argument {d} with value {}: {}\n", .{ store.index, self.operand_stack.items[0], self.locals.items[@intCast(store.index)] });
                    },
                    else => unreachable,
                }
            },
            .STI => {
                @panic("Not implemented");
            },
            .STA => {
                var value = try self.pop();
                const index = try self.pop();
                var aggregate = try self.pop();

                if (!aggregate.is_aggregate()) {
                    @panic("Aggregate expected");
                }

                const index_value: usize = @intCast(index.data);

                try aggregate.set_at(index_value, &value);

                try self.push(aggregate);
            },
            .DROP => {
                _ = try self.pop();
            },
            .LOAD => |load| {
                switch (load.rel) {
                    .G => {
                        try self.push(self.globals.items[@intCast(load.index)]);
                    },
                    .L => {
                        const local = self.get_local(@intCast(load.index)) orelse {
                            @panic("Local variable at not found in frame");
                        };
                        try self.push(local);
                    },
                    .A => {
                        const arg = self.get_argument(@intCast(load.index)) orelse {
                            @panic("Argument at not found in frame");
                        };
                        try self.push(arg);
                    },
                    else => unreachable,
                }
            },
            .LINE => |line| {
                util.dbgs("Line: {}\n", .{line.n});
            },
            .JMP => |jmp| {
                self.ip = @intCast(jmp.offset);
                // or?
                // self.ip = self.bf.code_section[@intCast(jmp.offset)];
            },
            .CJMP => |jmp| {
                // Condition value
                const value = try self.pop();
                switch (jmp.kind) {
                    .ISZERO => {
                        if (value.data == 0) self.ip = @intCast(jmp.offset);
                    },
                    .ISNONZERO => {
                        if (value.data != 0) self.ip = @intCast(jmp.offset);
                    },
                }
            },
            .ELEM => {
                const index = try self.pop();
                var aggregate = try self.pop();

                const index_value: usize = @intCast(index.data);

                // NOTE: verifying is moved to Object method
                const elem = try aggregate.get_at(index_value);
                try self.push(elem);
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
                0x3 => bt.Instruction.STI,
                0x4 => bt.Instruction.STA,
                0x5 => bt.Instruction{ .JMP = .{
                    .offset = try self.next(i32),
                } },
                0x6 => bt.Instruction.END,
                0x8 => bt.Instruction.DROP,
                0xb => bt.Instruction.ELEM,
                else => return InterpreterError.InvalidOpcode,
            },
            0x20 => bt.Instruction{ .LOAD = .{
                .index = try self.next(i32),
                .rel = @enumFromInt(subopcode),
            } },
            0x50 => switch (subopcode) {
                0x0 => bt.Instruction{ .CJMP = .{
                    .offset = try self.next(i32),
                    .kind = .ISZERO,
                } },
                0x1 => bt.Instruction{ .CJMP = .{
                    .offset = try self.next(i32),
                    .kind = .ISNONZERO,
                } },
                0x2 => bt.Instruction{ .BEGIN = .{
                    .args = try self.next(i32),
                    .locals = try self.next(i32),
                } },
                0xa => bt.Instruction{ .LINE = .{
                    .n = try self.next(i32),
                } },
                0x6 => bt.Instruction{ .CALL = .{
                    .builtin = false,
                    .offset = try self.next(i32),
                    .n = try self.next(i32),
                    .name = null,
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
                else => {
                    std.log.err("0x{X}\n", .{opcode});
                    return InterpreterError.InvalidOpcode;
                },
            },
            else => return InterpreterError.InvalidOpcode,
        };

        return instr;
    }
};
