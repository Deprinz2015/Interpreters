const DEBUG_TRACE_EXECUTION = @import("config").stack_trace;

const std = @import("std");
const Allocator = std.mem.Allocator;

const STACK_MAX = 256;

const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const Value = @import("value.zig").Value;
const Compiler = @import("Compiler.zig");
const debug = @import("debug.zig");

const VM = @This();

const InterpreterResult = enum {
    OK,
    COMPILE_ERROR,
    RUNTIME_ERROR,
};

const BinaryOperation = enum {
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
};

chunk: *Chunk = undefined,
ip: usize = 0,
stack: [STACK_MAX]Value = .{undefined} ** STACK_MAX,
stack_top: usize,

pub fn init() VM {
    return .{ .stack_top = 0 };
}

pub fn deinit(self: *VM) void {
    _ = self;
}

pub fn interpret(self: *VM, alloc: Allocator, source: []const u8) InterpreterResult {
    var chunk = Chunk.init(alloc);
    defer chunk.deinit();
    Compiler.compile(source, &chunk) catch {
        return .COMPILE_ERROR;
    };

    self.chunk = &chunk;
    self.ip = 0;

    const result = self.run();
    return result;
}

fn run(self: *VM) InterpreterResult {
    while (true) {
        if (comptime DEBUG_TRACE_EXECUTION) {
            std.debug.print("          ", .{});
            for (self.stack, 0..) |slot, i| {
                if (i >= self.stack_top) {
                    break;
                }
                std.debug.print("[ ", .{});
                debug.printValue(slot);
                std.debug.print(" ]", .{});
            }
            std.debug.print("\n", .{});
            _ = debug.disassembleInstruction(self.chunk, self.ip);
        }

        const byte = self.readByte();
        const instruction: OpCode = @enumFromInt(byte);
        switch (instruction) {
            .RETURN => {
                debug.printValue(self.pop());
                std.debug.print("\n", .{});
                return .OK;
            },
            .CONSTANT => {
                const constant = self.readConstant();
                self.push(constant);
            },
            .NEGATE => {
                self.push(-self.pop());
            },
            .ADD => self.binaryOp(.ADD),
            .SUBTRACT => self.binaryOp(.SUBTRACT),
            .MULTIPLY => self.binaryOp(.MULTIPLY),
            .DIVIDE => self.binaryOp(.DIVIDE),
        }
    }

    return .OK;
}

fn push(self: *VM, value: Value) void {
    self.stack[self.stack_top] = value;
    self.stack_top += 1;
}

fn pop(self: *VM) Value {
    self.stack_top -= 1;
    return self.stack[self.stack_top];
}

fn readByte(self: *VM) u8 {
    const ip = self.ip;
    self.ip += 1;
    return self.chunk.byteAt(ip);
}

fn readConstant(self: *VM) Value {
    return self.chunk.constants.at(self.readByte());
}

fn binaryOp(self: *VM, op: BinaryOperation) void {
    const b = self.pop();
    const a = self.pop();
    const result = switch (op) {
        .ADD => a + b,
        .SUBTRACT => a - b,
        .MULTIPLY => a * b,
        .DIVIDE => a / b,
    };
    self.push(result);
}
