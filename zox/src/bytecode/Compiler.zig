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
    TooManyLocals,
    JumpTooBig,
};

const TreeWalker = struct {
    code: std.ArrayList(u8),
    compiler: *Compiler,
    locals: [256][]const u8,
    locals_count: usize,
    enclosing: ?*TreeWalker,

    fn init(compiler: *Compiler, enclosing: ?*TreeWalker) TreeWalker {
        return .{
            .compiler = compiler,
            .code = .init(compiler.alloc),
            .locals = undefined,
            .locals_count = 0,
            .enclosing = enclosing,
        };
    }

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
                if (decl.initializer) |initializer| {
                    try self.traverseExpression(initializer);
                } else {
                    try self.writeOp(.NIL);
                }

                if (self.enclosing == null) {
                    const idx = try self.compiler.saveConstant(try String.copyString(decl.name.lexeme, self.compiler.alloc));
                    try self.writeOperand(.GLOBAL_DEFINE, idx);
                } else {
                    self.locals[self.locals_count] = decl.name.lexeme;
                    self.locals_count += 1;
                    try self.writeOp(.LOCAL_SET);
                }
            },
            .block => |block| {
                var walker: TreeWalker = .init(self.compiler, self);
                defer walker.code.deinit();

                for (block.stmts) |statement| {
                    try walker.traverseStatement(statement);
                }

                for (0..walker.locals_count) |_| {
                    try walker.writeOp(.LOCAL_POP);
                }

                const code = try walker.code.toOwnedSlice();
                defer self.compiler.alloc.free(code);

                try self.code.appendSlice(code);
            },
            .if_stmt => |if_stmt| {
                try self.traverseExpression(if_stmt.condition);

                const then = try self.writeJump(.JUMP_IF_FALSE);
                try self.writeOp(.POP);
                try self.traverseStatement(if_stmt.statement);

                const skip_else = try self.writeJump(.JUMP);
                try self.patchJump(then);
                try self.writeOp(.POP);

                if (if_stmt.else_stmt) |else_branch| {
                    try self.traverseStatement(else_branch);
                }
                try self.patchJump(skip_else);
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
            .variable => |variable| variable: {
                if (self.enclosing != null) {
                    const maybe_idx = try self.resolveLocal(variable.name.lexeme);
                    if (maybe_idx) |idx| {
                        try self.writeOperand(.LOCAL_GET, idx);
                        break :variable;
                    }
                }
                var name: String = .{ .value = variable.name.lexeme };
                const idx = try self.compiler.getConstant(.{ .string = &name });
                try self.writeOperand(.GLOBAL_GET, idx);
            },
            .assignment => |assignment| assignment: {
                try self.traverseExpression(assignment.value);
                if (self.enclosing != null) {
                    const maybe_idx = try self.resolveLocal(assignment.name.lexeme);
                    if (maybe_idx) |idx| {
                        try self.writeOperand(.LOCAL_SET_AT, idx);
                        break :assignment;
                    }
                }
                var name: String = .{ .value = assignment.name.lexeme };
                const idx = try self.compiler.getConstant(.{ .string = &name });
                try self.writeOperand(.GLOBAL_SET, idx);
            },
            else => unreachable,
        }
    }

    fn resolveLocal(self: *TreeWalker, name: []const u8) !?u8 {
        if (self.locals_count > 0) {
            for (self.locals, 0..) |local, i| {
                if (i >= self.locals_count) {
                    break;
                }
                if (std.mem.eql(u8, local, name)) {
                    return @intCast(self.locals_count - i);
                }
            }
        }

        if (self.enclosing) |enclosing| {
            const maybe_index = try enclosing.resolveLocal(name);
            if (maybe_index) |idx| {
                return @intCast(self.locals_count + idx);
            }
        }
        return null;
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

    fn writeJump(self: *TreeWalker, jump: Instruction) !usize {
        try self.writeOp(jump);
        try self.writeByte(0xff);
        try self.writeByte(0xff);
        return self.code.items.len - 2;
    }

    fn patchJump(self: *TreeWalker, jump_idx: usize) !void {
        const jump = self.code.items.len - jump_idx - 2;

        if (jump > std.math.maxInt(u16)) {
            return Error.JumpTooBig;
        }

        self.code.items[jump_idx] = @intCast((jump >> 8) & 0xff);
        self.code.items[jump_idx + 1] = @intCast(jump & 0xff);
    }
};

pub fn translate(program: []*ast.Stmt, alloc: Allocator) ![]u8 {
    var compiler: Compiler = .{
        .alloc = alloc,
        .program = program,
        .code = .init(alloc),
    };
    defer compiler.deinit();
    try compiler.compile();

    return try compiler.toBytecode();
}

fn deinit(self: *Compiler) void {
    for (self.constants, 0..) |constant, i| {
        if (i >= self.constants_count) {
            break;
        }
        constant.destroy(self.alloc);
    }
    self.code.deinit();
}

fn compile(self: *Compiler) !void {
    for (self.program) |stmt| {
        var walker: TreeWalker = .init(self, null);
        defer walker.code.deinit();

        try walker.traverseStatement(stmt);
        const code = try walker.code.toOwnedSlice();
        defer self.alloc.free(code);

        try self.code.appendSlice(code);
    }

    try self.insertConstants();
}

fn toBytecode(self: *Compiler) ![]u8 {
    return try self.code.toOwnedSlice();
}

fn insertConstants(self: *Compiler) !void {
    var constants_code: std.ArrayList(u8) = .init(self.alloc);
    defer constants_code.deinit();

    // Convert constants to bytecode
    for (self.constants, 0..) |constant, i| {
        if (i >= self.constants_count) {
            break;
        }
        switch (constant) {
            .number => {
                try constants_code.append(@intFromEnum(Instruction.NUMBER));
                try constants_code.appendSlice(&std.mem.toBytes(constant.number));
            },
            .string => {
                try constants_code.append(@intFromEnum(Instruction.STRING));
                // String length is written into 2 bytes
                const len = constant.string.value.len;
                if (len > std.math.maxInt(u16)) {
                    return Error.StringToLong;
                }
                try constants_code.append(@intCast((len >> 8) & 0xff));
                try constants_code.append(@intCast(len & 0xff));
                try constants_code.appendSlice(constant.string.value);
            },
            else => @panic("Unsupported constant type"),
        }
    }

    try constants_code.append(@intFromEnum(Instruction.CONSTANTS_DONE));
    const constants_code_raw = try constants_code.toOwnedSlice();
    defer self.alloc.free(constants_code_raw);

    try self.code.insertSlice(0, constants_code_raw);
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
