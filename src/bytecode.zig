//! Descriptor of Lama bytecode

const std = @import("std");

pub const Op = enum {
    ADD, // +
    SUB, // -
    MUL, // *
    DIV, // /
    MOD, // %
    LT, // <
    LEQ, // <=
    GT, // >
    GEQ, // >=
    EQ, // ==
    NEQ, // !=
    AND, // &&, Tests if both integer operands are non-zero
    OR, // ||, Tests if either of the operands is non-zero.
};

pub const ValueRel = enum {
    G, // Global
    L, // Local
    A, // Function argument
    C, // Captured by closure
};

pub const Instruction = union(enum) {
    NOP,
    /// See `Op` enum
    ///
    /// Example: BINOP ("*")
    BINOP: struct {
        op: Op,
    },
    /// Pushes the 𝑘th constant from the constant pool.
    CONST: struct {
        index: i32,
    },
    /// Pushes the 𝑠th string from the string table.
    STRING: struct {
        index: i32,
    },
    /// Marks the start of a procedure definition with
    /// 𝑎 arguments and 𝑛 locals.
    /// When executed, initializes locals to an empty
    /// value. Unlike CBEGIN, the defined procedure
    /// cannot use captured variables.
    ///
    /// Example: BEGIN ("main", 2, 0, [], [], [])
    BEGIN: struct {
        args: i32,
        locals: i32,
    },
    /// Store a value somewhere, depending on ValueRel
    ///
    /// Example: ST (Global ("z"))
    STORE: struct {
        rel: ValueRel,
        index: i32,
    },
    /// Load a value from somewhere, depending on ValueRel
    ///
    /// Example: LD (Global ("z"))
    LOAD: struct {
        rel: ValueRel,
        index: i32,
    },
    /// Call a function
    CALL: union(enum) {
        /// Calls a function with 𝑛 arguments. The bytecode for the
        /// function begins at 𝑙 (given as an offset from the start of the byte
        /// code). Pushes the returned value onto the stack.
        FUNC: struct {
            offset: i32,
            n: i32,
        },
        BUILTIN: struct {
            /// Name of the builtin function
            /// "Lread", "Lwrite", "Llength", "Lstring"
            name: []const u8,
        },
        // TODO: array
    },

    // pub fn decode(byte: u8) type {
    //     const opcode = byte & 0xF0;
    //     // const subopcode = byte & 0x0F;

    //     switch (opcode) {
    //         // BINOP
    //         0 => return @Type(Instruction.BINOP),
    //         // 1 => switch (subopcode) {
    //         //     // 0 => &Instruction{ .CONST = .{
    //         //     //     .index = operands;
    //         //     // } },

    //         //     else => null,
    //         // },
    //         // 5 => switch (subopcode) {
    //         //     2 => &Instruction{ .CONST = .{
    //         //         .index = subopcode,
    //         //     } },
    //         //     else => null,
    //         // },
    //         else => null,
    //     }
    // }
};
