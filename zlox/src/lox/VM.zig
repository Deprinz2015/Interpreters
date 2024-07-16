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

had_error: bool = false,
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
                std.debug.print("[ {} ]", .{slot});
            }
            std.debug.print("\n", .{});
            _ = debug.disassembleInstruction(self.chunk, self.ip);
        }

        const byte = self.readByte();
        const instruction: OpCode = @enumFromInt(byte);
        switch (instruction) {
            .RETURN => {
                std.debug.print("{}\n", .{self.pop()});
                return .OK;
            },
            .CONSTANT => {
                const constant = self.readConstant();
                self.push(constant);
            },
            .NIL => self.push(.NIL),
            .TRUE => self.push(.{ .BOOL = true }),
            .FALSE => self.push(.{ .BOOL = false }),
            .NEGATE => {
                if (self.peek(0) != .NUMBER) {
                    self.runtimeError("Operand must be a number.", .{});
                    break;
                }
                const value = self.pop().NUMBER;
                self.push(.{ .NUMBER = -value });
            },
            .ADD => self.binaryOp(.ADD),
            .SUBTRACT => self.binaryOp(.SUBTRACT),
            .MULTIPLY => self.binaryOp(.MULTIPLY),
            .DIVIDE => self.binaryOp(.DIVIDE),
        }

        if (self.had_error) {
            return .RUNTIME_ERROR;
        }
    }

    return .OK;
}

fn resetStack(self: *VM) void {
    self.stack_top = 0;
}

fn push(self: *VM, value: Value) void {
    self.stack[self.stack_top] = value;
    self.stack_top += 1;
}

fn pop(self: *VM) Value {
    self.stack_top -= 1;
    return self.stack[self.stack_top];
}

fn peek(self: *VM, index: usize) Value {
    return self.stack[self.stack_top - index];
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
    if (self.peek(0) != .NUMBER or self.peek(1) != .NUMBER) {
        self.runtimeError("Operands must be numbers.", .{});
        return;
    }

    const b = self.pop().NUMBER;
    const a = self.pop().NUMBER;
    const result = switch (op) {
        .ADD => a + b,
        .SUBTRACT => a - b,
        .MULTIPLY => a * b,
        .DIVIDE => a / b,
    };
    self.push(.{ .NUMBER = result });
}

fn runtimeError(self: *VM, comptime format: []const u8, args: anytype) void {
    const StdErr = std.io.getStdErr();
    StdErr.writer().print(format, args) catch {};
    StdErr.writer().writeByte('\n') catch {};

    const line = self.chunk.lines[self.ip - 1];
    StdErr.writer().print("[line {d}] in script\n", .{line}) catch {};
    self.resetStack();
    self.had_error = true;
}
