const std = @import("std");
const Allocator = std.mem.Allocator;
const Instruction = @import("../bytecode/instruction_set.zig").Instruction;
const Value = @import("../bytecode/value.zig").Value;

const Disassembler = @This();

alloc: Allocator,
code: []u8,
ip: usize,
constants: [256]Value,
constants_count: usize,

pub fn init(code: []u8, alloc: Allocator) Disassembler {
    return .{
        .alloc = alloc,
        .code = code,
        .ip = 0,
        .constants = undefined,
        .constants_count = 0,
    };
}

pub fn deinit(self: *Disassembler) void {
    for (self.constants, 0..) |constant, i| {
        if (i >= self.constants_count) break;

        if (constant == .string) {
            self.alloc.free(constant.string.value);
            self.alloc.destroy(constant.string);
        }
    }
}

fn loadConstants(self: *Disassembler) !void {
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
            else => unreachable,
        }
    }
}

pub fn print(self: *Disassembler) !void {
    if (self.code.len == 0) {
        return;
    }
    try self.loadConstants();

    self.ip = 0;
    while (self.ip < self.code.len) {
        std.debug.print("{x:0>4} ", .{self.ip});
        const instruction: Instruction = @enumFromInt(self.code[self.ip]);
        switch (instruction) {
            .CONSTANTS_DONE => self.simpleInstruction("OP_CONSTANTS_DONE"),
            .NUMBER => self.valueInstruction("OP_NUMBER", .number),
            .STRING => self.valueInstruction("OP_STRING", .string),
            .ADD => self.simpleInstruction("OP_ADD"),
            .SUB => self.simpleInstruction("OP_SUB"),
            .MUL => self.simpleInstruction("OP_MUL"),
            .DIV => self.simpleInstruction("OP_DIV"),
            .CONSTANT => self.constantInstruction("OP_CONSTANT"),
            .POP => self.simpleInstruction("OP_POP"),
            .PRINT => self.simpleInstruction("OP_PRINT"),
            .NIL => self.simpleInstruction("OP_NIL"),
            .TRUE => self.simpleInstruction("OP_TRUE"),
            .FALSE => self.simpleInstruction("OP_FALSE"),
            .NOT => self.simpleInstruction("OP_NOT"),
            .NEGATE => self.simpleInstruction("OP_NEGATE"),
            .EQUAL => self.simpleInstruction("OP_EQUAL"),
            .NOT_EQUAL => self.simpleInstruction("OP_NOT_EQUAL"),
            .LESS => self.simpleInstruction("OP_LESS"),
            .LESS_EQUAL => self.simpleInstruction("OP_LESS_EQUAL"),
            .GREATER => self.simpleInstruction("OP_GREATER"),
            .GREATER_EQUAL => self.simpleInstruction("OP_GREATER_EQUAL"),
            .GLOBAL_DEFINE => self.constantInstruction("OP_GLOBAL_DEFINE"),
            .GLOBAL_GET => self.constantInstruction("OP_GLOBAL_GET"),
            .GLOBAL_SET => self.constantInstruction("OP_GLOBAL_SET"),
        }
    }
}

fn simpleInstruction(self: *Disassembler, name: []const u8) void {
    std.debug.print("{s}\n", .{name});
    self.ip += 1;
}

fn valueInstruction(self: *Disassembler, name: []const u8, value_type: std.meta.Tag(Value)) void {
    std.debug.print("{s: <24} ", .{name});
    var new_ip: usize = 0;
    switch (value_type) {
        .number => {
            const value = std.mem.bytesToValue(f64, self.code[self.ip + 1 .. self.ip + 9]);
            std.debug.print("{d}", .{value});
            new_ip = 8;
        },
        .string => {
            const len = len: {
                const lhs: u16 = @intCast(self.code[self.ip + 1]);
                const rhs: u16 = @intCast(self.code[self.ip + 2]);
                break :len (lhs << 8) | rhs;
            };

            const value = self.code[self.ip + 3 .. self.ip + 3 + len];
            std.debug.print("{s}", .{value});

            new_ip = 2 + len;
        },
        else => @panic("Unsupported value type"),
    }
    std.debug.print("\n", .{});
    self.ip += new_ip + 1;
}

fn constantInstruction(self: *Disassembler, name: []const u8) void {
    const idx = self.code[self.ip + 1];
    const constant = self.constants[idx];
    std.debug.print("{s: <24} {d: <8} {}\n", .{ name, idx, constant });
    self.ip += 2;
}
