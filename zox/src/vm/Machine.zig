const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("../bytecode/value.zig").Value;
const Instruction = @import("../bytecode/instruction_set.zig").Instruction;
const StdOut = std.io.getStdOut().writer();
const StdErr = std.io.getStdErr().writer();

const VM = @This();

const STACK_MAX = 256;

alloc: Allocator,
constants: [256]Value,
constants_count: usize,
globals: std.StringHashMap(Value),
locals: [256]Value,
locals_count: usize,
code: []const u8,
ip: usize,
stack: []Value,
stack_top: usize,
has_error: bool,

const Error = error{
    UnexpectedInstruction,
    StackOverflow,
    IOError,
    TypeError,
    RuntimeError,
};

pub fn init(alloc: Allocator, program: []const u8) !VM {
    return .{
        .alloc = alloc,
        .constants = undefined,
        .constants_count = 0,
        .locals = undefined,
        .locals_count = 0,
        .globals = .init(alloc),
        .code = program,
        .ip = 0,
        .stack = try alloc.alloc(Value, STACK_MAX),
        .stack_top = 0,
        .has_error = false,
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
        // TODO: When adding GC, go through everpart where a value is popped and check for unexpected frees
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
                    try self.runtimeError("Negation only works on numbers", .{});
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
                if (name != .string) unreachable; // weird
                const value = self.pop();
                try self.globals.put(name.string.value, value);
            },
            .GLOBAL_GET => {
                const idx = self.readByte();
                const name = self.constants[idx];
                if (name != .string) unreachable; // weird
                if (self.globals.get(name.string.value)) |val| {
                    try self.push(val);
                } else {
                    try self.runtimeError("Undefined global '{s}'", .{name.string.value});
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
                    try self.globals.put(name.string.value, self.peek(0));
                } else {
                    try self.runtimeError("Undefined global '{s}'", .{name.string.value});
                }
            },
            .LOCAL_POP => self.locals_count -= 1,
            .LOCAL_GET => {
                const idx = self.readByte();
                try self.push(self.localAt(idx));
            },
            .LOCAL_SET => {
                self.pushLocal(self.pop());
            },
            .LOCAL_SET_AT => {
                const idx = self.readByte();
                self.setLocalAt(idx, self.peek(0));
            },
            .JUMP => {
                const jump = self.readShort();
                self.ip += jump;
            },
            .JUMP_BACK => {
                const jump = self.readShort();
                self.ip -= jump;
            },
            .JUMP_IF_FALSE => {
                const jump = self.readShort();
                if (self.peek(0).isFalsey()) {
                    self.ip += jump;
                }
            },
            .JUMP_IF_TRUE => {
                const jump = self.readShort();
                if (!self.peek(0).isFalsey()) {
                    self.ip += jump;
                }
            },
        }
        // @import("../debug/Stack.zig").print(self.stack, self.stack_top);

        if (self.has_error) {
            return Error.RuntimeError;
        }
    }
}

fn binaryOp(self: *VM, op: Instruction) !void {
    const right = self.pop();
    const left = self.pop();

    if (left != .number or right != .number) {
        try self.runtimeError("Binary operation expects operands to be of type number. Got {} and {}", .{ std.meta.activeTag(left), std.meta.activeTag(right) });
        return Error.TypeError;
    }

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

fn readShort(self: *VM) u16 {
    const lhs: u16 = @intCast(self.code[self.ip]);
    const rhs: u16 = @intCast(self.code[self.ip + 1]);
    self.ip += 2;
    return (lhs << 8) | rhs;
}

fn peek(self: *VM, idx: usize) Value {
    return self.stack[self.stack_top - 1 - idx];
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
        try self.runtimeError("Stack overflow", .{});
        return Error.StackOverflow;
    }
    self.stack[self.stack_top] = value;
    self.stack_top += 1;
}

fn localAt(self: *VM, idx: usize) Value {
    return self.locals[self.locals_count - idx];
}

fn setLocalAt(self: *VM, idx: usize, value: Value) void {
    self.locals[self.locals_count - idx] = value;
}

fn pushLocal(self: *VM, value: Value) void {
    self.locals[self.locals_count] = value;
    self.locals_count += 1;
}

fn printValue(value: Value) !void {
    StdOut.print("{}", .{value}) catch return Error.IOError;
}

fn printLiteral(str: []const u8) !void {
    StdOut.writeAll(str) catch return Error.IOError;
}

fn runtimeError(self: *VM, comptime format: []const u8, args: anytype) !void {
    self.has_error = true;
    StdErr.print(format, args) catch return Error.IOError;
}
