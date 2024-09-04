const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("../bytecode/value.zig").Value;
const Instruction = @import("../bytecode/instruction_set.zig").Instruction;
const StdOut = std.io.getStdOut().writer();

const VM = @This();

const STACK_MAX = 256;

alloc: Allocator,
constants: [256]Value,
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
        .code = program,
        .ip = 0,
        .stack = try alloc.alloc(Value, STACK_MAX),
        .stack_top = 0,
    };
}

pub fn deinit(self: *VM) void {
    self.alloc.free(self.stack);
}

pub fn execute(self: *VM) !void {
    try self.loadConstants();
    try self.run();
}

fn loadConstants(self: *VM) !void {
    var constants_count: usize = 0;
    var idx: usize = 0;
    while (idx < self.code.len) {
        const code = self.code[idx];
        switch (code) {
            @intFromEnum(Instruction.CONSTANTS_DONE) => {
                self.ip = idx + 1;
                return;
            },
            @intFromEnum(Instruction.NUMBER) => {
                const number = std.mem.bytesToValue(f64, self.code[idx + 1 .. idx + 9]);
                self.constants[constants_count] = .{ .number = number };
                constants_count += 1;
                idx += 9; // 1 for instruction + 8 for 64-bit float
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
            .NUMBER, .CONSTANTS_DONE => return Error.UnexpectedInstruction,
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
