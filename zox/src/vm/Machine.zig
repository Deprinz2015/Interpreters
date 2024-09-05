const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("../bytecode/value.zig").Value;
const Instruction = @import("../bytecode/instruction_set.zig").Instruction;
const StdOut = std.io.getStdOut().writer();

const VM = @This();

const STACK_MAX = 256;

alloc: Allocator,
constants: [256]Value,
constants_count: usize,
globals: std.StringHashMap(Value),
code: []const u8,
ip: usize,
stack: []Value,
stack_top: usize,

const Error = error{
    UnexpectedInstruction,
    StackOverflow,
    IOError,
    TypeError,
};

pub fn init(alloc: Allocator, program: []const u8) !VM {
    return .{
        .alloc = alloc,
        .constants = undefined,
        .constants_count = 0,
        .globals = .init(alloc),
        .code = program,
        .ip = 0,
        .stack = try alloc.alloc(Value, STACK_MAX),
        .stack_top = 0,
    };
}

pub fn deinit(self: *VM) void {
    self.globals.deinit();
    self.alloc.free(self.stack);
    for (self.constants, 0..) |value, i| {
        if (i >= self.constants_count) {
            break;
        }

        value.destroy(self.alloc);
    }
}

pub fn execute(self: *VM) !void {
    try self.loadConstants();
    try self.run();
}

fn loadConstants(self: *VM) !void {
    var idx: usize = 0;
    while (idx < self.code.len) {
        const code = self.code[idx];
        const instruction: Instruction = @enumFromInt(code);
        switch (instruction) {
            .CONSTANTS_DONE => {
                self.ip = idx + 1;
                return;
            },
            .NUMBER => {
                const number = std.mem.bytesToValue(f64, self.code[idx + 1 .. idx + 9]);
                self.constants[self.constants_count] = .{ .number = number };
                self.constants_count += 1;
                idx += 9; // 1 for instruction + 8 for 64-bit float
            },
            .STRING => {
                const len = len: {
                    const lhs: u16 = @intCast(self.code[idx + 1]);
                    const rhs: u16 = @intCast(self.code[idx + 2]);
                    break :len (lhs << 8) | rhs;
                };

                const value = self.code[idx + 3 .. idx + 3 + len];
                self.constants[self.constants_count] = try Value.String.copyString(value, self.alloc);
                self.constants_count += 1;
                idx += 1 + 2 + len; // 1 for instruction, 2 for len, len of string
            },
            else => return Error.UnexpectedInstruction,
        }
    }
}

fn run(self: *VM) !void {
    while (self.ip < self.code.len) {
        const byte = self.readByte();
        const instruction: Instruction = @enumFromInt(byte);
        switch (instruction) {
            .NUMBER, .STRING, .CONSTANTS_DONE => return Error.UnexpectedInstruction,
            .POP => _ = self.pop(),
            .NOT => {
                const value = self.pop();
                try self.push(.{ .boolean = value.isFalsey() });
            },
            .NEGATE => {
                const value = self.pop();
                if (value != .number) {
                    return Error.TypeError;
                }
                try self.push(.{ .number = value.number * -1 });
            },
            .ADD, .SUB, .MUL, .DIV => try self.binaryOp(instruction),
            .EQUAL, .NOT_EQUAL, .LESS, .LESS_EQUAL, .GREATER, .GREATER_EQUAL => try self.equalityOp(instruction),
            .CONSTANT => {
                const idx = self.readByte();
                try self.push(self.constants[idx]);
            },
            .PRINT => {
                const value = self.pop();
                try printValue(value);
                try printLiteral("\n");
            },
            .TRUE => try self.push(.{ .boolean = true }),
            .FALSE => try self.push(.{ .boolean = false }),
            .NIL => try self.push(.nil),
            .GLOBAL_DEFINE => {
                const idx = self.readByte();
                const name = self.constants[idx];
                if (name != .string) {
                    // weird
                    unreachable;
                }
                const value = self.pop();
                try self.globals.put(name.string.value, value);
            },
            .GLOBAL_GET => {
                const idx = self.readByte();
                const name = self.constants[idx];
                if (name != .string) {
                    // weird
                    unreachable;
                }
                if (self.globals.get(name.string.value)) |val| {
                    try self.push(val);
                } else {
                    // undefined global
                    // TODO: This needs to be better handled
                    unreachable;
                }
            },
            .GLOBAL_SET => {
                const idx = self.readByte();
                const name = self.constants[idx];
                if (name != .string) {
                    // weird
                    unreachable;
                }
                if (self.globals.get(name.string.value)) |_| {
                    const value = self.pop();
                    try self.globals.put(name.string.value, value);
                    try self.push(value);
                } else {
                    // undefined global
                    // TODO: This needs to be better handled
                    unreachable;
                }
            },
        }
        // @import("../debug/Stack.zig").print(self.stack, self.stack_top);
    }
}

fn binaryOp(self: *VM, op: Instruction) !void {
    const right = self.pop();
    const left = self.pop();

    // TODO: Typechecks
    // TODO: Special treatment for string concats later

    const result = switch (op) {
        .ADD => left.number + right.number,
        .SUB => left.number - right.number,
        .MUL => left.number * right.number,
        .DIV => left.number / right.number,
        else => unreachable,
    };
    try self.push(.{ .number = result });
}

fn equalityOp(self: *VM, op: Instruction) !void {
    const right = self.pop();
    const left = self.pop();

    // TODO: Type check for less and greater operations

    const result = switch (op) {
        .EQUAL => left.equals(right),
        .NOT_EQUAL => !left.equals(right),
        .LESS => left.number < right.number,
        .LESS_EQUAL => left.number <= right.number,
        .GREATER => left.number > right.number,
        .GREATER_EQUAL => left.number >= right.number,
        else => unreachable,
    };

    try self.push(.{ .boolean = result });
}

fn readByte(self: *VM) u8 {
    const byte = self.code[self.ip];
    self.ip += 1;
    return byte;
}

fn pop(self: *VM) Value {
    if (self.stack_top == 0) {
        @panic("Stack cannot be lowered");
    }

    self.stack_top -= 1;
    return self.stack[self.stack_top];
}

fn push(self: *VM, value: Value) !void {
    if (self.stack_top == STACK_MAX) {
        return Error.StackOverflow;
    }
    self.stack[self.stack_top] = value;
    self.stack_top += 1;
}

fn printValue(value: Value) !void {
    StdOut.print("{}", .{value}) catch return Error.IOError;
}

fn printLiteral(str: []const u8) !void {
    StdOut.writeAll(str) catch return Error.IOError;
}
