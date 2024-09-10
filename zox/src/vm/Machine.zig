const std = @import("std");
const Allocator = std.mem.Allocator;
const GC = @import("GC.zig");
const Value = @import("value.zig").Value;
const Instruction = @import("../instruction_set.zig").Instruction;
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
strings: std.StringHashMap(void),
code: []const u8,
gc: GC,
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
        .strings = .init(alloc),
        .globals = .init(alloc),
        .code = program,
        .gc = .init(alloc),
        .ip = 0,
        .stack = try alloc.alloc(Value, STACK_MAX),
        .stack_top = 0,
        .has_error = false,
    };
}

pub fn deinit(self: *VM) void {
    self.globals.deinit();
    for (self.constants, 0..) |constant, i| {
        if (i >= self.constants_count) {
            break;
        }

        self.gc.countDown(constant);
    }
    self.alloc.free(self.stack);
    var string_iter = self.strings.keyIterator();
    while (string_iter.next()) |string| {
        self.alloc.free(string.*);
    }
    self.strings.deinit();
    self.gc.deinit();
}

pub fn execute(self: *VM) !void {
    try self.loadConstants();
    try self.run();
}

/// Interns the given string.
/// If it is not yet existent, adds it to set and returns it as is.
/// Otherwise frees the memory of the passed string and returns the already saved string. Usage of the passed string is not safe.
fn internString(self: *VM, string: []const u8) ![]const u8 {
    if (self.strings.getKey(string)) |interned_string| {
        self.alloc.free(string);
        return interned_string;
    }

    try self.strings.put(string, undefined);
    return string;
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
                const string = try Value.String.copyString(value, self.alloc);
                try self.gc.countUp(string);
                self.constants[self.constants_count] = string;
                try self.strings.put(string.string.value, undefined);
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
                    try self.runtimeError("Negation only works on numbers", .{});
                    return Error.TypeError;
                }
                try self.push(.{ .number = value.number * -1 });
            },
            .ADD => {
                const right = self.peek(0);
                const left = self.peek(1);

                if (right == .number and left == .number) {
                    try self.binaryOp(instruction);
                } else {
                    try self.concat();
                }
            },
            .SUB, .MUL, .DIV => try self.binaryOp(instruction),
            .EQUAL, .NOT_EQUAL => try self.equalityOp(instruction),
            .LESS, .LESS_EQUAL, .GREATER, .GREATER_EQUAL => try self.comparisonOp(instruction),
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
                try self.gc.countUp(value);
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
                if (self.globals.get(name.string.value)) |old_value| {
                    try self.globals.put(name.string.value, self.peek(0));
                    try self.gc.countUp(name);
                    self.gc.countDown(old_value);
                } else {
                    try self.runtimeError("Undefined global '{s}'", .{name.string.value});
                }
            },
            .LOCAL_POP => {
                self.locals_count -= 1;
                self.gc.countDown(self.locals[self.locals_count]);
            },
            .LOCAL_GET => {
                const idx = self.readByte();
                try self.push(self.localAt(idx));
            },
            .LOCAL_SET => {
                try self.pushLocal(self.pop());
            },
            .LOCAL_SET_AT => {
                const idx = self.readByte();
                try self.setLocalAt(idx, self.peek(0));
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

fn concat(self: *VM) !void {
    const right = self.pop();
    const left = self.pop();

    if (left != .string and right != .string) {
        try self.runtimeError("Add Operation can only be performed on two numbers or at least one string. Got '{s}' and '{s}'", .{ left.typeName(), right.typeName() });
        return Error.TypeError;
    }

    const concatted = try std.fmt.allocPrint(self.alloc, "{}{}", .{ left, right });
    const interned = try self.internString(concatted);
    const result = try Value.String.takeString(interned, self.alloc);
    self.gc.countDown(left);
    self.gc.countDown(right);
    try self.gc.countUp(result);
    try self.push(result);
}

fn binaryOp(self: *VM, op: Instruction) !void {
    const right = self.pop();
    const left = self.pop();

    if (left != .number or right != .number) {
        try self.runtimeError("Binary operation expects operands to be of type number. Got {s} and {s}", .{ left.typeName(), right.typeName() });
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

    const result = switch (op) {
        .EQUAL => left.equals(right),
        .NOT_EQUAL => !left.equals(right),
        else => unreachable,
    };

    try self.push(.{ .boolean = result });
}

fn comparisonOp(self: *VM, op: Instruction) !void {
    const right = self.pop();
    const left = self.pop();

    if (right != .number) {
        try self.runtimeError("Comparison Operator expects right operand to be number. Found '{}' of type '{s}'.", .{ right, right.typeName() });
        return Error.TypeError;
    }

    if (left != .number) {
        try self.runtimeError("Comparison Operator expects left operand to be number. Found '{}' of type '{s}'.", .{ left, left.typeName() });
        return Error.TypeError;
    }

    const result = switch (op) {
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

fn setLocalAt(self: *VM, idx: usize, value: Value) !void {
    const old = self.localAt(idx);
    self.locals[self.locals_count - idx] = value;
    self.gc.countDown(old);
}

fn pushLocal(self: *VM, value: Value) !void {
    self.locals[self.locals_count] = value;
    self.locals_count += 1;
    try self.gc.countUp(value);
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
    StdErr.writeAll("\n") catch return Error.IOError;
}
