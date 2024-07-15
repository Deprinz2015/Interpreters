const std = @import("std");

const DEBUG_TRACE_EXECUTION = false;
const STACK_MAX = 256;

const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const Value = @import("value.zig").Value;
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
stack_top: [*]Value,

pub fn init() VM {
    var vm: VM = .{
        .stack_top = undefined,
    };
    vm.stack_top = &vm.stack;
    return vm;
}

pub fn deinit(self: *VM) void {
    _ = self;
}

pub fn interpret(self: *VM, chunk: *Chunk) InterpreterResult {
    self.chunk = chunk;
    self.ip = 0;
    return self.run();
}

fn run(self: *VM) InterpreterResult {
    while (true) {
        if (comptime DEBUG_TRACE_EXECUTION) {
            std.debug.print("          ", .{});
            for (self.stack) |slot| {
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
    self.stack_top[0] = value;
    self.stack_top += 1;
}

fn pop(self: *VM) Value {
    self.stack_top -= 1;
    return self.stack_top[0];
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
