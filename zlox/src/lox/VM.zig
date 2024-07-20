const DEBUG_TRACE_EXECUTION = @import("config").stack_trace;

const std = @import("std");
const Allocator = std.mem.Allocator;
const StdOut = std.io.getStdOut();

const STACK_MAX = 256;

const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const Value = @import("value.zig").Value;
const Obj = @import("value.zig").Obj;
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
objects: ?*Obj = null,
strings: std.StringHashMap(*Obj.String),
globals: std.StringHashMap(Value),
ip: usize = 0,
stack: [STACK_MAX]Value = .{undefined} ** STACK_MAX,
stack_top: usize,
alloc: Allocator,

pub fn init(alloc: Allocator) VM {
    return .{
        .stack_top = 0,
        .alloc = alloc,
        .strings = std.StringHashMap(*Obj.String).init(alloc),
        .globals = std.StringHashMap(Value).init(alloc),
    };
}

pub fn deinit(self: *VM) void {
    self.deinitObjects();
    self.strings.deinit();
    self.globals.deinit();
}

fn deinitObjects(self: *VM) void {
    while (self.objects) |obj| {
        const next = obj.next;
        self.freeObject(obj);
        self.objects = next;
    }
}

fn freeObject(self: *VM, obj: *Obj) void {
    switch (obj.as) {
        .STRING => {
            const str = obj.as.STRING;
            self.alloc.free(str.string());
            self.alloc.destroy(str);
            self.alloc.destroy(obj);
        },
    }
}

pub fn interpret(self: *VM, alloc: Allocator, source: []const u8) InterpreterResult {
    var chunk = Chunk.init(alloc);
    defer chunk.deinit();
    Compiler.compile(alloc, self, source, &chunk) catch {
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
            if (self.stack_top == 0) {
                std.debug.print("[ empty stack ]", .{});
            }
            std.debug.print("\n", .{});
            _ = debug.disassembleInstruction(self.chunk, self.ip);
        }

        const byte = self.readByte();
        const instruction: OpCode = @enumFromInt(byte);
        switch (instruction) {
            .PRINT => StdOut.writer().print("{}\n", .{self.pop()}) catch unreachable,
            .POP => _ = self.pop(),
            .JUMP => {
                const offset = self.readShort();
                self.ip += offset;
            },
            .JUMP_IF_FALSE => {
                const offset = self.readShort();
                if (isFalsey(self.peek(0))) {
                    self.ip += offset;
                }
            },
            .LOOP => {
                const offset = self.readShort();
                self.ip -= offset;
            },
            .DEFINE_GLOBAL => {
                const name = self.readConstant().OBJ.as.STRING;
                self.globals.put(name.string(), self.peek(0)) catch unreachable;
                _ = self.pop();
            },
            .GET_GLOBAL => get: {
                const name = self.readConstant().OBJ.as.STRING;
                const value = self.globals.get(name.string());
                if (value == null) {
                    self.runtimeError("Undefined variable '{s}'.", .{name.string()});
                    break :get;
                }
                self.push(value.?);
            },
            .SET_GLOBAL => set: {
                const name = self.readConstant().OBJ.as.STRING;
                const value = self.globals.get(name.string());
                if (value == null) {
                    self.runtimeError("Undefined variable '{s}'.", .{name.string()});
                    break :set;
                }
                self.globals.put(name.string(), self.peek(0)) catch unreachable;
            },
            .GET_LOCAL => {
                const slot = self.readByte();
                self.push(self.stack[slot]);
            },
            .SET_LOCAL => {
                const slot = self.readByte();
                self.stack[slot] = self.peek(0);
            },
            .RETURN => {
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
            .ADD => add: {
                if (self.peek(0) == .NUMBER and self.peek(1) == .NUMBER) {
                    self.binaryOp(.ADD);
                    break :add;
                }

                if (Value.isObjType(self.peek(0), .STRING) and Value.isObjType(self.peek(1), .STRING)) {
                    self.concat();
                    break :add;
                }

                self.runtimeError("Operands must be two numbers or two strings.", .{});
                break;
            },
            .SUBTRACT, .MULTIPLY, .DIVIDE, .LESS, .GREATER => |op| self.binaryOp(op),
            .NOT => self.push(.{ .BOOL = isFalsey(self.pop()) }),
            .EQUAL => {
                const b = self.pop();
                const a = self.pop();
                self.push(.{ .BOOL = valuesEqual(a, b) });
            },
        }

        if (self.had_error) {
            self.had_error = false;
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
    return self.stack[self.stack_top - index - 1];
}

fn readByte(self: *VM) u8 {
    const ip = self.ip;
    self.ip += 1;
    return self.chunk.byteAt(ip);
}

fn readShort(self: *VM) u16 {
    const ip = self.ip;
    self.ip += 2;
    const lhs: u16 = @intCast(self.chunk.byteAt(ip));
    return (lhs << 8) | self.chunk.byteAt(ip + 1);
}

fn readConstant(self: *VM) Value {
    return self.chunk.constants.at(self.readByte());
}

fn binaryOp(self: *VM, op: OpCode) void {
    if (self.peek(0) != .NUMBER or self.peek(1) != .NUMBER) {
        self.runtimeError("Operands must be numbers. '{}' and '{}'", .{ self.peek(1), self.peek(0) });
        return;
    }

    const b = self.pop().NUMBER;
    const a = self.pop().NUMBER;
    const result: Value = switch (op) {
        .ADD => .{ .NUMBER = a + b },
        .SUBTRACT => .{ .NUMBER = a - b },
        .MULTIPLY => .{ .NUMBER = a * b },
        .DIVIDE => .{ .NUMBER = a / b },
        .LESS => .{ .BOOL = a < b },
        .GREATER => .{ .BOOL = a > b },
        else => unreachable,
    };
    self.push(result);
}

fn concat(self: *VM) void {
    const str_b = self.pop().OBJ.as.STRING;
    const str_a = self.pop().OBJ.as.STRING;

    const chars = std.mem.concat(self.alloc, u8, &[_][]const u8{ str_a.string(), str_b.string() }) catch unreachable;
    const result = Obj.takeString(self.alloc, chars, self);
    self.push(.{ .OBJ = result });
}

fn isFalsey(value: Value) bool {
    if (value == .NIL) {
        return true;
    }

    if (value == .BOOL) {
        return !value.BOOL;
    }

    return false;
}

fn valuesEqual(a: Value, b: Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) {
        return false;
    }

    return switch (a) {
        .NIL => true,
        .BOOL => a.BOOL == b.BOOL,
        .NUMBER => a.NUMBER == b.NUMBER,
        .OBJ => switch (a.OBJ.as) {
            .STRING => {
                if (b.OBJ.as != .STRING) {
                    return false;
                }

                const str_a = a.OBJ.as.STRING;
                const str_b = b.OBJ.as.STRING;
                return str_a == str_b;
            },
        },
    };
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
