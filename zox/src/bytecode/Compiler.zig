const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("../compiler/ast.zig");
const Instruction = @import("instruction_set.zig").Instruction;
const Value = @import("value.zig").Value;

const Compiler = @This();

code: std.ArrayList(u8),
constants: [256]Value = undefined, // Max 256 constants are allowed
constants_count: usize = 0,
alloc: Allocator,
program: []*ast.Stmt,

const Error = error{
    TooManyConstants,
};

const TreeWalker = struct {
    code: std.ArrayList(u8),
    compiler: *Compiler,

    fn traverseStatement(self: *TreeWalker, stmt: *ast.Stmt) !void {
        switch (stmt.*) {
            .expression => {
                try self.traverseExpression(stmt.expression.expr);
                try self.code.append(@intFromEnum(Instruction.POP));
            },
            else => unreachable,
        }
    }

    fn traverseExpression(self: *TreeWalker, expr: *ast.Expr) !void {
        switch (expr.*) {
            .binary => |binary| {
                try self.traverseExpression(binary.left);
                try self.traverseExpression(binary.right);
                switch (binary.op.type) {
                    .@"+" => try self.writeOp(.ADD),
                    .@"-" => try self.writeOp(.SUB),
                    .@"*" => try self.writeOp(.MUL),
                    .@"/" => try self.writeOp(.DIV),
                    else => unreachable,
                }
            },
            .literal => |literal| {
                const value: Value = switch (literal.value) {
                    .number => |num| .{ .number = num },
                    else => unreachable,
                };
                const idx = try self.compiler.saveConstant(value);
                try self.writeOperand(.CONSTANT, idx);
            },
            else => unreachable,
        }
    }

    fn writeOp(self: *TreeWalker, op: Instruction) !void {
        try self.writeByte(@intFromEnum(op));
    }

    fn writeByte(self: *TreeWalker, byte: u8) !void {
        try self.code.append(byte);
    }

    fn writeOperand(self: *TreeWalker, op: Instruction, operand: u8) !void {
        try self.writeOp(op);
        try self.writeByte(operand);
    }
};

pub fn translate(program: []*ast.Stmt, alloc: Allocator) ![]u8 {
    var compiler: Compiler = .{
        .alloc = alloc,
        .program = program,
        .code = .init(alloc),
    };
    try compiler.compile();

    return try compiler.toBytecode();
}

fn compile(self: *Compiler) !void {
    for (self.program) |stmt| {
        var walker: TreeWalker = .{
            .code = .init(self.alloc),
            .compiler = self,
        };
        defer walker.code.deinit();

        try walker.traverseStatement(stmt);
        const code = try walker.code.toOwnedSlice();
        defer self.alloc.free(code);

        try self.code.appendSlice(code);
    }
}

fn toBytecode(self: *Compiler) ![]u8 {
    defer self.code.deinit();

    var complete_code: std.ArrayList(u8) = .init(self.alloc);
    defer complete_code.deinit();

    // Convert constants to bytecode
    for (self.constants, 0..) |constant, i| {
        if (i >= self.constants_count) {
            break;
        }
        switch (constant) {
            .number => {
                try complete_code.append(@intFromEnum(Instruction.NUMBER));
                try complete_code.appendSlice(&std.mem.toBytes(constant.number));
            },
        }
    }

    // All Constants are in front of the rest of the code
    try complete_code.append(@intFromEnum(Instruction.CONSTANTS_DONE));
    const code = try self.code.toOwnedSlice();
    defer self.alloc.free(code);
    try complete_code.appendSlice(code);
    return try complete_code.toOwnedSlice();
}

fn saveConstant(self: *Compiler, value: Value) !u8 {
    if (self.constants_count >= self.constants.len) {
        return Error.TooManyConstants;
    }

    for (self.constants, 0..) |constant, i| {
        if (i >= self.constants_count) {
            break;
        }

        if (constant.equals(value)) {
            return @intCast(i);
        }
    }

    self.constants[self.constants_count] = value;
    self.constants_count += 1;
    return @intCast(self.constants_count - 1);
}
