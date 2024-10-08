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
const GC = @import("GC.zig");

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
    closure: *Obj.Closure,
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
open_upvalues: ?*Obj.Upvalue,
alloc: Allocator,
gc: *GC,

pub fn init(alloc: Allocator, gc: *GC) VM {
    var vm: VM = .{
        .stack = alloc.alloc(Value, STACK_MAX) catch unreachable,
        .frames = alloc.alloc(CallFrame, FRAMES_MAX) catch unreachable,
        .stack_top = 0,
        .alloc = undefined,
        .strings = std.StringHashMap(*Obj.String).init(alloc),
        .globals = std.StringHashMap(Value).init(alloc),
        .open_upvalues = null,
        .gc = gc,
    };

    vm.gc.vm = &vm;
    vm.alloc = vm.gc.allocator();

    vm.defineNative("clock", &NativeFunctions.clock);
    vm.defineNative("print", &NativeFunctions.print);
    vm.defineNative("read", &NativeFunctions.read);
    vm.defineNative("count", &NativeFunctions.count);

    return vm;
}

pub fn deinit(self: *VM) void {
    self.deinitObjects();
    self.strings.deinit();
    self.globals.deinit();
    self.gc.child_alloc.free(self.stack);
    self.gc.child_alloc.free(self.frames);
}

fn deinitObjects(self: *VM) void {
    while (self.objects) |obj| {
        const next = obj.next;
        obj.destroy(self.alloc);
        self.objects = next;
    }
}

pub fn interpret(self: *VM, source: []const u8) InterpreterResult {
    const function = Compiler.compile(self.alloc, self, source) catch {
        return .COMPILE_ERROR;
    };

    self.push(.{ .OBJ = &function.obj });
    const closure = Obj.Closure.create(self.alloc, function, self);
    _ = self.pop();
    self.push(.{ .OBJ = &closure.obj });
    self.call(closure, 0) catch {
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
            _ = debug.disassembleInstruction(&frame.closure.function.chunk, frame.ip);
        }

        const byte = self.readByte();
        const instruction: OpCode = @enumFromInt(byte);
        switch (instruction) {
            .POP => _ = self.pop(),
            .CLOSE_UPVALUE => {
                self.closeUpvalues(&self.stack[self.stack_top - 1]);
                _ = self.pop();
            },
            .CLOSURE => {
                const function = self.readConstant().OBJ.as(.FUNCTION);
                const closure = Obj.Closure.create(self.alloc, function, self);
                self.push(.{ .OBJ = &closure.obj });
                var idx: usize = 0;
                while (idx < closure.upvalue_count) : (idx += 1) {
                    const is_local = self.readByte() == 1;
                    const index = self.readByte();
                    if (is_local) {
                        closure.upvalues[idx] = self.captureUpvalue(&frame.slots[index]);
                    } else {
                        closure.upvalues[idx] = frame.closure.upvalues[index];
                    }
                }
            },
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
                const name = self.readConstant().OBJ.as(.STRING);
                self.globals.put(name.chars, self.peek(0)) catch unreachable;
                _ = self.pop();
            },
            .GET_GLOBAL => get: {
                const name = self.readConstant().OBJ.as(.STRING);
                const value = self.globals.get(name.chars);
                if (value == null) {
                    self.runtimeError("Undefined variable '{s}'.", .{name.chars});
                    break :get;
                }
                self.push(value.?);
            },
            .SET_GLOBAL => set: {
                const name = self.readConstant().OBJ.as(.STRING);
                const value = self.globals.get(name.chars);
                if (value == null) {
                    self.runtimeError("Undefined variable '{s}'.", .{name.chars});
                    break :set;
                }
                self.globals.put(name.chars, self.peek(0)) catch unreachable;
            },
            .GET_LOCAL => {
                const slot = self.readByte();
                self.push(frame.slots[slot]);
            },
            .SET_LOCAL => {
                const slot = self.readByte();
                frame.slots[slot] = self.peek(0);
            },
            .GET_UPVALUE => {
                const slot = self.readByte();
                self.push(frame.closure.upvalues[slot].?.location.*);
            },
            .SET_UPVALUE => {
                const slot = self.readByte();
                frame.closure.upvalues[slot].?.location.* = self.peek(0);
            },
            .GET_ARRAY => arr: {
                const key_arg = self.peek(0);
                const array_arg = self.peek(1);
                if (!array_arg.isObjType(.ARRAY)) {
                    self.runtimeError("Can only use index syntax on arrays", .{});
                    break :arr;
                }
                const array = array_arg.OBJ.as(.ARRAY);
                if (key_arg == .NUMBER) {
                    if (std.math.modf(key_arg.NUMBER).fpart != 0) {
                        self.runtimeError("Can only index with whole numbers", .{});
                        break :arr;
                    }
                    const key = std.fmt.allocPrint(self.alloc, "{d:.0}", .{key_arg.NUMBER}) catch unreachable;
                    defer self.alloc.free(key);
                    if (array.values.get(key)) |value| {
                        _ = self.pop(); // key
                        _ = self.pop(); // array
                        self.push(value);
                        break :arr;
                    }
                    self.runtimeError("Key not found: {s}", .{key});
                    break :arr;
                }

                self.runtimeError("Can only index using whole numbers.", .{});
            },
            .SET_ARRAY => arr: {
                const value = self.peek(0);
                const key_arg = self.peek(1);
                const array_arg = self.peek(2);
                if (!array_arg.isObjType(.ARRAY)) {
                    self.runtimeError("Can only use index syntax on arrays", .{});
                    break :arr;
                }
                const array = array_arg.OBJ.as(.ARRAY);
                if (key_arg == .NUMBER) {
                    if (std.math.modf(key_arg.NUMBER).fpart != 0) {
                        self.runtimeError("Can only index with whole numbers", .{});
                        break :arr;
                    }
                    const key = std.fmt.allocPrint(self.alloc, "{d:.0}", .{key_arg.NUMBER}) catch unreachable;
                    const exists = array.values.get(key) != null;
                    array.values.put(key, value) catch unreachable;
                    if (exists) {
                        self.alloc.free(key);
                    }
                    break :arr;
                }

                self.runtimeError("Can only index using whole numbers.", .{});
            },
            .APPEND => arr: {
                const value = self.peek(0);
                const array_arg = self.peek(1);
                if (!array_arg.isObjType(.ARRAY)) {
                    self.runtimeError("Can only use index syntax on arrays", .{});
                    break :arr;
                }
                const array = array_arg.OBJ.as(.ARRAY);
                const key = std.fmt.allocPrint(self.alloc, "{d}", .{array.values.count()}) catch unreachable;
                array.values.put(key, value) catch unreachable;
            },
            .ARRAY => {
                const value_count = self.readByte();
                var idx = value_count;
                const arr = Obj.Array.create(self.alloc, self);
                self.push(.{ .OBJ = &arr.obj });
                while (idx > 0) : (idx -= 1) {
                    const key = std.fmt.allocPrint(self.alloc, "{d}", .{arr.values.count()}) catch unreachable;
                    const value = self.peek(idx);
                    arr.values.put(key, value) catch unreachable;
                }
                for (0..value_count) |_| {
                    _ = self.pop();
                }
                _ = self.pop();
                self.push(.{ .OBJ = &arr.obj });
            },
            .RETURN => {
                const result = self.pop();
                self.closeUpvalues(&frame.slots[0]);
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

fn defineNative(self: *VM, name: []const u8, function: Obj.Native.NativeFn) void {
    const str = Obj.String.copy(self.alloc, name, self);
    const native = Obj.Native.create(self.alloc, function, self);
    self.push(.{ .OBJ = &str.obj });
    self.push(.{ .OBJ = &native.obj });
    self.globals.put(name, self.stack[1]) catch unreachable;
    _ = self.pop();
    _ = self.pop();
}

fn resetStack(self: *VM) void {
    self.stack_top = 0;
}

pub fn push(self: *VM, value: Value) void {
    self.stack[self.stack_top] = value;
    self.stack_top += 1;
}

pub fn pop(self: *VM) Value {
    self.stack_top -= 1;
    return self.stack[self.stack_top];
}

fn peek(self: *VM, index: usize) Value {
    return self.stack[self.stack_top - index - 1];
}

fn captureUpvalue(self: *VM, local: *Value) *Obj.Upvalue {
    var prev_upvalue: ?*Obj.Upvalue = null;
    var current_upvalue = self.open_upvalues;
    while (current_upvalue != null and @intFromPtr(current_upvalue.?.location) > @intFromPtr(local)) {
        prev_upvalue = current_upvalue;
        current_upvalue = current_upvalue.?.next;
    }

    if (current_upvalue) |upvalue| {
        if (upvalue.location == local) {
            return upvalue;
        }
    }

    const upvalue = Obj.Upvalue.create(self.alloc, local, self);
    upvalue.next = current_upvalue;

    if (prev_upvalue) |prev| {
        prev.next = upvalue;
    } else {
        self.open_upvalues = upvalue;
    }

    return upvalue;
}

fn closeUpvalues(self: *VM, last: *Value) void {
    while (self.open_upvalues != null and @intFromPtr(self.open_upvalues.?.location) >= @intFromPtr(last)) {
        const upvalue = self.open_upvalues.?;
        upvalue.closed = upvalue.location.*;
        upvalue.location = &upvalue.closed;
        self.open_upvalues = upvalue.next;
    }
}

const RuntimeError = error{
    RUNTIME_ERROR,
    STACK_OVERFLOW,
};

fn callValue(self: *VM, callee: Value, arg_count: usize) RuntimeError!void {
    if (callee == .OBJ) {
        switch (callee.OBJ.type) {
            .CLOSURE => {
                return self.call(callee.OBJ.as(.CLOSURE), arg_count);
            },
            .NATIVE => {
                const native = callee.OBJ.as(.NATIVE);
                const result = native.function(self.stack[self.stack_top - arg_count .. self.stack_top], self);
                if (self.had_error) {
                    return;
                }
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

fn call(self: *VM, closure: *Obj.Closure, arg_count: usize) RuntimeError!void {
    const function = closure.function;
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
        .closure = closure,
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
    return frame.closure.function.chunk.byteAt(ip);
}

fn readShort(self: *VM) u16 {
    const frame = self.currentFrame();
    const ip = frame.ip;
    frame.ip += 2;
    const lhs: u16 = @intCast(frame.closure.function.chunk.byteAt(ip));
    return (lhs << 8) | frame.closure.function.chunk.byteAt(ip + 1);
}

fn readConstant(self: *VM) Value {
    return self.currentFrame().closure.function.chunk.constantAt(self.readByte());
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
    const b = self.peek(0);
    const a = self.peek(1);
    const chars = std.fmt.allocPrint(self.alloc, "{}{}", .{ a, b }) catch unreachable;
    const result = Obj.String.take(self.alloc, chars, self);
    _ = self.pop();
    _ = self.pop();
    self.push(.{ .OBJ = &result.obj });
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
            if (obj_a.type != obj_b.type) {
                return false;
            }
            switch (obj_a.type) {
                .STRING => {
                    const str_a = obj_a.as(.STRING);
                    const str_b = obj_b.as(.STRING);
                    return str_a == str_b;
                },
                .FUNCTION => {
                    const fun_a = obj_a.as(.FUNCTION);
                    const fun_b = obj_b.as(.FUNCTION);
                    return fun_a.name == fun_b.name;
                },
                .NATIVE => {
                    const fun_a = obj_a.as(.NATIVE);
                    const fun_b = obj_b.as(.NATIVE);
                    return fun_a == fun_b;
                },
                .CLOSURE => {
                    const clos_a = obj_a.as(.CLOSURE);
                    const clos_b = obj_b.as(.CLOSURE);
                    return clos_a == clos_b;
                },
                .UPVALUE => {
                    const up_a = obj_a.as(.UPVALUE);
                    const up_b = obj_b.as(.UPVALUE);
                    return valuesEqual(up_a.location.*, up_b.location.*);
                },
                .ARRAY => {
                    const arr_a = obj_a.as(.ARRAY);
                    const arr_b = obj_b.as(.ARRAY);
                    if (arr_a.values.count() != arr_b.values.count()) {
                        return false;
                    }

                    // Compare every value of array
                    var values_a = arr_a.values.iterator();
                    while (values_a.next()) |val_a| {
                        const key = val_a.key_ptr.*;
                        if (arr_b.values.get(key) == null) {
                            return false;
                        }

                        if (!valuesEqual(val_a.value_ptr.*, arr_b.values.get(key).?)) {
                            return false;
                        }
                    }
                    return true;
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
        const function = frame.closure.function;
        StdErr.writer().print("[line {d}] in ", .{function.chunk.lines[frame.ip - 1]}) catch {};
        if (function.name) |name| {
            StdErr.writer().print("{s}()\n", .{name.chars}) catch {};
        } else {
            StdErr.writeAll("script\n") catch {};
        }
    }
    self.resetStack();
    self.had_error = true;
}

const NativeFunctions = struct {
    const StdIn = std.io.getStdIn();

    fn clock(args: []Value, vm: *VM) Value {
        if (args.len != 0) {
            vm.runtimeError("native function 'clock' does not expect any arguments. Got {d} arguments.", .{args.len});
            return .NIL;
        }

        const timestamp: f64 = @floatFromInt(std.time.milliTimestamp());
        return .{ .NUMBER = timestamp / std.time.ms_per_s };
    }

    fn print(args: []Value, vm: *VM) Value {
        if (args.len != 1) {
            vm.runtimeError("native function 'print' expects 1 argument, got {d} arguments.", .{args.len});
            return .NIL;
        }

        StdOut.writer().print("{}\n", .{args[0]}) catch unreachable;
        return .NIL;
    }

    fn read(args: []Value, vm: *VM) Value {
        if (args.len != 1 and args.len != 2) {
            vm.runtimeError("native function 'read' expects 1 or 2 arguments, got {d} arguments.", .{args.len});
            return .NIL;
        }

        const new_line = new_line: {
            if (args.len != 2) {
                break :new_line false;
            }
            if (args[1] != .BOOL) {
                vm.runtimeError("native function 'read' expects second argument to be bool.", .{});
                return .NIL;
            }

            break :new_line args[1].BOOL;
        };

        StdOut.writer().print("{}", .{args[0]}) catch unreachable;
        if (new_line) {
            StdOut.writeAll("\n") catch unreachable;
        }
        const alloc = vm.alloc;
        const input = StdIn.reader().readUntilDelimiterAlloc(alloc, '\n', 1024) catch unreachable;
        defer alloc.free(input);
        const floatVal = std.fmt.parseFloat(f64, input) catch {
            const string = Obj.String.copy(alloc, input, vm);
            return .{ .OBJ = &string.obj };
        };
        return .{ .NUMBER = floatVal };
    }

    fn count(args: []Value, vm: *VM) Value {
        if (args.len != 1) {
            vm.runtimeError("native function 'count' expects exactly one argument, got {d} arguments.", .{args.len});
            return .NIL;
        }

        const array = args[0];
        if (array != .OBJ or !array.isObjType(.ARRAY)) {
            vm.runtimeError("native function 'count' expects argument to be array.", .{});
            return .NIL;
        }

        return .{ .NUMBER = @floatFromInt(array.OBJ.as(.ARRAY).values.count()) };
    }
};
