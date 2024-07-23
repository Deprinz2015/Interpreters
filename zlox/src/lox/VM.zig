const DEBUG_TRACE_EXECUTION = @import("config").stack_trace;

const std = @import("std");
const Allocator = std.mem.Allocator;
const StdOut = std.io.getStdOut();

const FRAMES_MAX = 64;
const STACK_MAX = FRAMES_MAX * std.math.maxInt(u8);

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

const CallFrame = struct {
    function: *Obj.Function,
    ip: usize,
    slots: [*]Value,
    return_adress: usize,
};

had_error: bool = false,
frames: []CallFrame,
frame_count: usize = 0,
objects: ?*Obj = null,
strings: std.StringHashMap(*Obj.String),
globals: std.StringHashMap(Value),
stack: []Value,
stack_top: usize,
alloc: Allocator,

pub fn init(alloc: Allocator) VM {
    var vm: VM = .{
        .stack = alloc.alloc(Value, STACK_MAX) catch unreachable,
        .frames = alloc.alloc(CallFrame, FRAMES_MAX) catch unreachable,
        .stack_top = 0,
        .alloc = alloc,
        .strings = std.StringHashMap(*Obj.String).init(alloc),
        .globals = std.StringHashMap(Value).init(alloc),
    };

    vm.defineNative("clock", &NativeFunctions.clock);
    vm.defineNative("print", &NativeFunctions.print);
    vm.defineNative("read", &NativeFunctions.read);

    return vm;
}

pub fn deinit(self: *VM) void {
    self.deinitObjects();
    self.strings.deinit();
    self.globals.deinit();
    self.alloc.free(self.stack);
    self.alloc.free(self.frames);
}

fn deinitObjects(self: *VM) void {
    while (self.objects) |obj| {
        const next = obj.next;
        self.freeObject(obj);
        self.objects = next;
    }
}

fn freeObject(self: *VM, obj: *Obj) void {
    defer self.alloc.destroy(obj);
    switch (obj.as) {
        .STRING => {
            const str = obj.as.STRING;
            self.alloc.free(str.string());
            self.alloc.destroy(str);
        },
        .FUNCTION => {
            const function = obj.as.FUNCTION;
            function.chunk.deinit();
            self.alloc.destroy(function);
        },
        .NATIVE => {
            const function = obj.as.NATIVE;
            self.alloc.destroy(function);
        },
    }
}

pub fn interpret(self: *VM, alloc: Allocator, source: []const u8) InterpreterResult {
    const function = Compiler.compile(alloc, self, source) catch {
        return .COMPILE_ERROR;
    };

    self.push(.{ .OBJ = function.obj });
    self.call(function, 0) catch {
        return .RUNTIME_ERROR;
    };

    return self.run();
}

fn run(self: *VM) InterpreterResult {
    var frame = self.currentFrame();
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
            _ = debug.disassembleInstruction(&frame.function.chunk, frame.ip);
        }

        const byte = self.readByte();
        const instruction: OpCode = @enumFromInt(byte);
        switch (instruction) {
            .POP => _ = self.pop(),
            .CALL => {
                const arg_count = self.readByte();
                self.callValue(self.peek(arg_count), arg_count) catch {
                    return .RUNTIME_ERROR;
                };
                frame = self.currentFrame();
            },
            .JUMP => {
                const offset = self.readShort();
                frame.ip += offset;
            },
            .JUMP_IF_FALSE => {
                const offset = self.readShort();
                if (isFalsey(self.peek(0))) {
                    frame.ip += offset;
                }
            },
            .LOOP => {
                const offset = self.readShort();
                frame.ip -= offset;
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
                self.push(frame.slots[slot]);
            },
            .SET_LOCAL => {
                const slot = self.readByte();
                frame.slots[slot] = self.peek(0);
            },
            .RETURN => {
                const result = self.pop();
                self.frame_count -= 1;
                if (self.frame_count == 0) {
                    _ = self.pop();
                    return .OK;
                }

                self.stack_top = frame.return_adress;
                self.push(result);
                frame = self.currentFrame();
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

                if (Value.isObjType(self.peek(0), .STRING) or Value.isObjType(self.peek(1), .STRING)) {
                    self.concat();
                    break :add;
                }

                self.runtimeError("Operands must be two numbers or at least a strings.", .{});
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

fn defineNative(self: *VM, name: []const u8, function: Obj.NativeFunction.NativeFn) void {
    self.push(.{ .OBJ = Obj.copyString(self.alloc, name, self) });
    self.push(.{ .OBJ = Obj.createNativeFunction(self.alloc, function, self) });
    self.globals.put(name, self.stack[1]) catch unreachable;
    _ = self.pop();
    _ = self.pop();
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

const RuntimeError = error{
    RUNTIME_ERROR,
    STACK_OVERFLOW,
};

fn callValue(self: *VM, callee: Value, arg_count: usize) RuntimeError!void {
    if (callee == .OBJ) {
        switch (callee.OBJ.as) {
            .FUNCTION => |func| {
                return self.call(func, arg_count);
            },
            .NATIVE => |native| {
                const result = native.function(self.stack[self.stack_top - arg_count ..], self.alloc, self);
                self.stack_top -= arg_count + 1;
                self.push(result);
                return;
            },
            else => {},
        }
    }

    self.runtimeError("Can only call functions and classes.", .{});
    return RuntimeError.RUNTIME_ERROR;
}

fn call(self: *VM, function: *Obj.Function, arg_count: usize) RuntimeError!void {
    if (arg_count != function.arity) {
        self.runtimeError("Expected {d} arguments but got {d}", .{ function.arity, arg_count });
        return RuntimeError.RUNTIME_ERROR;
    }

    if (self.frame_count == FRAMES_MAX) {
        self.runtimeError("Stack overflow", .{});
        return RuntimeError.STACK_OVERFLOW;
    }

    const frame = &self.frames[self.frame_count];
    self.frame_count += 1;
    const frame_start = self.stack_top - arg_count - 1;
    frame.* = .{
        .function = function,
        .ip = 0,
        .slots = self.stack[frame_start..].ptr,
        .return_adress = frame_start,
    };
}

fn currentFrame(self: *VM) *CallFrame {
    return &self.frames[self.frame_count - 1];
}

fn readByte(self: *VM) u8 {
    const frame = self.currentFrame();
    const ip = frame.ip;
    frame.ip += 1;
    return frame.function.chunk.byteAt(ip);
}

fn readShort(self: *VM) u16 {
    const frame = self.currentFrame();
    const ip = frame.ip;
    frame.ip += 2;
    const lhs: u16 = @intCast(frame.function.chunk.byteAt(ip));
    return (lhs << 8) | frame.function.chunk.byteAt(ip + 1);
}

fn readConstant(self: *VM) Value {
    return self.currentFrame().function.chunk.constantAt(self.readByte());
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
    const b = self.pop();
    const a = self.pop();
    const chars = std.fmt.allocPrint(self.alloc, "{}{}", .{ a, b }) catch unreachable;
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
        .OBJ => |obj_a| {
            const obj_b = b.OBJ;
            if (std.meta.activeTag(obj_a.as) != std.meta.activeTag(obj_b.as)) {
                return false;
            }
            switch (obj_a.as) {
                .STRING => |str_a| {
                    const str_b = obj_b.as.STRING;
                    return str_a == str_b;
                },
                .FUNCTION => |fun_a| {
                    const fun_b = obj_b.as.FUNCTION;
                    return fun_a.name == fun_b.name;
                },
                .NATIVE => |fun_a| {
                    const fun_b = obj_b.as.NATIVE;
                    return fun_a == fun_b;
                },
            }
        },
    };
}

fn runtimeError(self: *VM, comptime format: []const u8, args: anytype) void {
    const StdErr = std.io.getStdErr();
    StdErr.writer().print(format, args) catch {};
    StdErr.writer().writeByte('\n') catch {};

    var i: usize = 0;
    while (i < self.frame_count) : (i += 1) {
        const frame = self.frames[self.frame_count - 1 - i];
        const function = frame.function;
        StdErr.writer().print("[line {d}] in ", .{function.chunk.lines[frame.ip - 1]}) catch {};
        if (function.name) |name| {
            StdErr.writer().print("{s}()\n", .{name.string()}) catch {};
        } else {
            StdErr.writeAll("script\n") catch {};
        }
    }
    self.resetStack();
    self.had_error = true;
}

const NativeFunctions = struct {
    const StdIn = std.io.getStdIn();

    fn clock(_: []Value, _: Allocator, _: *VM) Value {
        const timestamp: f64 = @floatFromInt(std.time.milliTimestamp());
        return .{ .NUMBER = timestamp / std.time.ms_per_s };
    }

    fn print(args: []Value, _: Allocator, _: *VM) Value {
        StdOut.writer().print("{}\n", .{args[0]}) catch unreachable;
        return .NIL;
    }

    fn read(args: []Value, alloc: Allocator, vm: *VM) Value {
        StdOut.writer().print("{}\n", .{args[0]}) catch unreachable;
        const input = StdIn.reader().readUntilDelimiterAlloc(alloc, '\n', 1024) catch unreachable;
        defer alloc.free(input);
        const floatVal = std.fmt.parseFloat(f64, input) catch {
            return .{ .OBJ = Obj.copyString(alloc, input, vm) };
        };
        return .{ .NUMBER = floatVal };
    }
};
