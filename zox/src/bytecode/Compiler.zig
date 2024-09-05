const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("../compiler/ast.zig");
const Instruction = @import("instruction_set.zig").Instruction;
const Value = @import("value.zig").Value;
const String = Value.String;

const Compiler = @This();

code: std.ArrayList(u8),
constants: [256]Value = undefined, // Max 256 constants are allowed
constants_count: usize = 0,
alloc: Allocator,
program: []*ast.Stmt,

const Error = error{
    TooManyConstants,
    StringToLong,
    ConstantNotFound,
};

const TreeWalker = struct {
    code: std.ArrayList(u8),
    compiler: *Compiler,
    toplevel: bool,

    fn traverseStatement(self: *TreeWalker, stmt: *ast.Stmt) !void {
        switch (stmt.*) {
            .expression => {
                try self.traverseExpression(stmt.expression.expr);
                try self.writeOp(.POP);
            },
            .print => {
                try self.traverseExpression(stmt.print.expr);
                try self.writeOp(.PRINT);
            },
            .var_stmt => |decl| {
                if (decl.initializer) |init| {
                    try self.traverseExpression(init);
                } else {
                    try self.writeOp(.NIL);
                }
                const idx = try self.compiler.saveConstant(try String.copyString(decl.name.lexeme, self.compiler.alloc));
                if (self.toplevel) {
                    try self.writeOperand(.GLOBAL_DEFINE, idx);
                } else {
                    unreachable; // Locals are not supported yet
                }
            },
            else => unreachable,
        }
    }

    fn traverseExpression(self: *TreeWalker, expr: *ast.Expr) !void {
        switch (expr.*) {
            .unary => |unary| {
                try self.traverseExpression(unary.expr);
                switch (unary.op.type) {
                    .@"!" => try self.writeOp(.NOT),
                    .@"-" => try self.writeOp(.NEGATE),
                    else => unreachable,
                }
            },
            .binary => |binary| {
                try self.traverseExpression(binary.left);
                try self.traverseExpression(binary.right);
                switch (binary.op.type) {
                    .@"+" => try self.writeOp(.ADD),
                    .@"-" => try self.writeOp(.SUB),
                    .@"*" => try self.writeOp(.MUL),
                    .@"/" => try self.writeOp(.DIV),
                    .@"==" => try self.writeOp(.EQUAL),
                    .@"!=" => try self.writeOp(.NOT_EQUAL),
                    .@"<" => try self.writeOp(.LESS),
                    .@"<=" => try self.writeOp(.LESS_EQUAL),
                    .@">" => try self.writeOp(.GREATER),
                    .@">=" => try self.writeOp(.GREATER_EQUAL),
                    else => unreachable,
                }
            },
            .literal => |literal| switch (literal.value) {
                .number => |num| {
                    const idx = try self.compiler.saveConstant(.{ .number = num });
                    try self.writeOperand(.CONSTANT, idx);
                },
                .boolean => |b| try self.writeOp(if (b) .TRUE else .FALSE),
                .nil => try self.writeOp(.NIL),
                .string => |str| {
                    const idx = try self.compiler.saveConstant(try String.copyString(str, self.compiler.alloc));
                    try self.writeOperand(.CONSTANT, idx);
                },
            },
            .variable => |variable| {
                if (self.toplevel) {
                    var name: String = .{ .value = variable.name.lexeme };
                    const idx = try self.compiler.getConstant(.{ .string = &name });
                    try self.writeOperand(.GLOBAL_GET, idx);
                } else {
                    unreachable; // Locals are not supported yet
                }
            },
            .assignment => |assignment| {
                if (self.toplevel) {
                    var name: String = .{ .value = assignment.name.lexeme };
                    const idx = try self.compiler.getConstant(.{ .string = &name });
                    try self.traverseExpression(assignment.value);
                    try self.writeOperand(.GLOBAL_SET, idx);
                } else {
                    unreachable; // Locals are not supported yet
                }
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
            .toplevel = true,
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
            .string => {
                try complete_code.append(@intFromEnum(Instruction.STRING));
                // String length is written into 2 bytes
                const len = constant.string.value.len;
                if (len > std.math.maxInt(u16)) {
                    return Error.StringToLong;
                }
                try complete_code.append(@intCast((len >> 8) & 0xff));
                try complete_code.append(@intCast(len & 0xff));
                try complete_code.appendSlice(constant.string.value);
                // appendSlice copies the memory, so we can safely free it here
                constant.destroy(self.alloc);
            },
            else => @panic("Unsupported constant type"),
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

        if (constant == .string and value == .string) {
            if (std.mem.eql(u8, constant.string.value, value.string.value)) {
                value.destroy(self.alloc);
                return @intCast(i);
            }
        }
    }

    self.constants[self.constants_count] = value;
    self.constants_count += 1;
    return @intCast(self.constants_count - 1);
}

fn getConstant(self: *Compiler, value: Value) !u8 {
    for (self.constants, 0..) |constant, i| {
        if (i >= self.constants_count) {
            break;
        }

        if (constant.equals(value)) {
            return @intCast(i);
        }

        if (constant == .string and value == .string) {
            if (std.mem.eql(u8, constant.string.value, value.string.value)) {
                return @intCast(i);
            }
        }
    }
    return Error.ConstantNotFound;
}
