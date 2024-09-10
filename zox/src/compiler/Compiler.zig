const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");
const Instruction = @import("../instruction_set.zig").Instruction;
const Value = @import("value.zig").Value;

const Compiler = @This();

code: std.ArrayList(u8),
constants: [256]Value = undefined, // Max 256 constants are allowed
constants_count: usize = 0,
alloc: Allocator,
program: []*ast.Stmt,
has_error: bool = false,

const Error = error{
    TooManyConstants,
    StringToLong,
    ConstantNotFound,
    TooManyLocals,
    JumpTooBig,
    CompileError,
};

// TODO: Extract some functions out for readability?
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

    fn traverseStatement(self: *TreeWalker, stmt: *ast.Stmt) void {
        switch (stmt.*) {
            .expression => {
                self.traverseExpression(stmt.expression.expr);
                self.writeOp(.POP);
            },
            .print => {
                self.traverseExpression(stmt.print.expr);
                self.writeOp(.PRINT);
            },
            .var_stmt => |decl| {
                if (decl.initializer) |initializer| {
                    self.traverseExpression(initializer);
                } else {
                    self.writeOp(.NIL);
                }

                if (self.enclosing == null) {
                    const string: Value = .{ .string = decl.name.lexeme };
                    const idx = self.compiler.saveConstant(string) catch {
                        printError("Could not save constant string '{s}'", .{decl.name.lexeme});
                        self.compiler.has_error = true;
                        return;
                    };
                    self.writeOperand(.GLOBAL_DEFINE, idx);
                } else {
                    self.locals[self.locals_count] = decl.name.lexeme;
                    self.locals_count += 1;
                    self.writeOp(.LOCAL_SET);
                }
            },
            .block => |block| {
                var walker: TreeWalker = .init(self.compiler, self);
                defer walker.code.deinit();

                for (block.stmts) |statement| {
                    walker.traverseStatement(statement);
                }

                for (0..walker.locals_count) |_| {
                    walker.writeOp(.LOCAL_POP);
                }

                const code = walker.code.toOwnedSlice() catch @panic("Out of Memory");
                defer self.compiler.alloc.free(code);

                self.code.appendSlice(code) catch @panic("Out of Memory");
            },
            .if_stmt => |if_stmt| {
                self.traverseExpression(if_stmt.condition);

                const then = self.writeJump(.JUMP_IF_FALSE);
                self.writeOp(.POP);
                self.traverseStatement(if_stmt.statement);

                const skip_else = self.writeJump(.JUMP);
                self.patchJump(then);
                self.writeOp(.POP);

                if (if_stmt.else_stmt) |else_branch| {
                    self.traverseStatement(else_branch);
                }
                self.patchJump(skip_else);
            },
            .while_stmt => |while_stmt| {
                const loop_start = self.code.items.len;
                self.traverseExpression(while_stmt.condition);
                const exit = self.writeJump(.JUMP_IF_FALSE);
                self.writeOp(.POP);
                self.traverseStatement(while_stmt.statement);
                self.writeJumpComplete(.JUMP_BACK, self.code.items.len + 3 - loop_start);
                self.patchJump(exit);
                self.writeOp(.POP);
            },
            else => unreachable,
        }
    }

    fn traverseExpression(self: *TreeWalker, expr: *ast.Expr) void {
        switch (expr.*) {
            .unary => |unary| {
                self.traverseExpression(unary.expr);
                switch (unary.op.type) {
                    .@"!" => self.writeOp(.NOT),
                    .@"-" => self.writeOp(.NEGATE),
                    else => unreachable,
                }
            },
            .binary => |binary| {
                self.traverseExpression(binary.left);
                self.traverseExpression(binary.right);
                switch (binary.op.type) {
                    .@"+" => self.writeOp(.ADD),
                    .@"-" => self.writeOp(.SUB),
                    .@"*" => self.writeOp(.MUL),
                    .@"/" => self.writeOp(.DIV),
                    .@"==" => self.writeOp(.EQUAL),
                    .@"!=" => self.writeOp(.NOT_EQUAL),
                    .@"<" => self.writeOp(.LESS),
                    .@"<=" => self.writeOp(.LESS_EQUAL),
                    .@">" => self.writeOp(.GREATER),
                    .@">=" => self.writeOp(.GREATER_EQUAL),
                    else => unreachable,
                }
            },
            .literal => |literal| switch (literal.value) {
                .number => |num| {
                    const idx = self.compiler.saveConstant(.{ .number = num }) catch {
                        printError("Could not save constant number '{d}'", .{num});
                        self.compiler.has_error = true;
                        return;
                    };
                    self.writeOperand(.CONSTANT, idx);
                },
                .boolean => |b| self.writeOp(if (b) .TRUE else .FALSE),
                .nil => self.writeOp(.NIL),
                .string => |str| {
                    const string: Value = .{ .string = str };
                    const idx = self.compiler.saveConstant(string) catch {
                        printError("Could not save constant string '{s}'", .{str});
                        self.compiler.has_error = true;
                        return;
                    };
                    self.writeOperand(.CONSTANT, idx);
                },
            },
            .variable => |variable| variable: {
                if (self.enclosing != null) {
                    const maybe_idx = self.resolveLocal(variable.name.lexeme);
                    if (maybe_idx) |idx| {
                        self.writeOperand(.LOCAL_GET, idx);
                        break :variable;
                    }
                }
                const name: Value = .{ .string = variable.name.lexeme };
                const idx = self.compiler.saveConstant(name) catch {
                    printError("Could not save constant string '{s}'", .{name.string});
                    self.compiler.has_error = true;
                    return;
                };
                self.writeOperand(.GLOBAL_GET, idx);
            },
            .assignment => |assignment| assignment: {
                self.traverseExpression(assignment.value);
                if (self.enclosing != null) {
                    const maybe_idx = self.resolveLocal(assignment.name.lexeme);
                    if (maybe_idx) |idx| {
                        self.writeOperand(.LOCAL_SET_AT, idx);
                        break :assignment;
                    }
                }
                const name: Value = .{ .string = assignment.name.lexeme };
                const idx = self.compiler.saveConstant(name) catch {
                    printError("Could not save constant string '{s}'", .{name.string});
                    self.compiler.has_error = true;
                    return;
                };
                self.writeOperand(.GLOBAL_SET, idx);
            },
            .logical => |logical| {
                self.traverseExpression(logical.left);
                const jump_type: Instruction = switch (logical.op.type) {
                    .AND => .JUMP_IF_FALSE,
                    .OR => .JUMP_IF_TRUE,
                    else => unreachable,
                };
                const jump = self.writeJump(jump_type);
                self.writeOp(.POP);
                self.traverseExpression(logical.right);
                self.patchJump(jump);
            },
            .call => |call| {
                for (call.arguments) |arg| {
                    self.traverseExpression(arg);
                }
                self.traverseExpression(call.callee);
                self.writeOperand(.CALL, @intCast(call.arguments.len));
            },
        }
    }

    fn resolveLocal(self: *TreeWalker, name: []const u8) ?u8 {
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
            const maybe_index = enclosing.resolveLocal(name);
            if (maybe_index) |idx| {
                return @intCast(self.locals_count + idx);
            }
        }
        return null;
    }

    fn writeOp(self: *TreeWalker, op: Instruction) void {
        self.writeByte(@intFromEnum(op));
    }

    fn writeByte(self: *TreeWalker, byte: u8) void {
        self.code.append(byte) catch @panic("Out of Memory");
    }

    fn writeOperand(self: *TreeWalker, op: Instruction, operand: u8) void {
        self.writeOp(op);
        self.writeByte(operand);
    }

    fn writeJump(self: *TreeWalker, jump: Instruction) usize {
        self.writeOp(jump);
        self.writeByte(0xff);
        self.writeByte(0xff);
        return self.code.items.len - 2;
    }

    fn writeJumpComplete(self: *TreeWalker, jump: Instruction, idx: usize) void {
        if (idx > std.math.maxInt(u16)) {
            printError("Too much code to jump: {d}", .{idx});
            self.compiler.has_error = true;
        }

        self.writeOp(jump);
        self.writeByte(@intCast((idx >> 8) & 0xff));
        self.writeByte(@intCast(idx & 0xff));
    }

    fn patchJump(self: *TreeWalker, jump_idx: usize) void {
        const jump = self.code.items.len - jump_idx - 2;

        if (jump > std.math.maxInt(u16)) {
            printError("Too much code to jump: {d}", .{jump});
            self.compiler.has_error = true;
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

    if (compiler.has_error) {
        return Error.CompileError;
    }

    return try compiler.toBytecode();
}

fn deinit(self: *Compiler) void {
    self.code.deinit();
}

fn compile(self: *Compiler) !void {
    for (self.program) |stmt| {
        var walker: TreeWalker = .init(self, null);
        defer walker.code.deinit();

        walker.traverseStatement(stmt);
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
                const len = constant.string.len;
                if (len > std.math.maxInt(u16)) {
                    return Error.StringToLong;
                }
                try constants_code.append(@intCast((len >> 8) & 0xff));
                try constants_code.append(@intCast(len & 0xff));
                try constants_code.appendSlice(constant.string);
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
            if (constant.equals(value)) {
                return @intCast(i);
            }
        }
    }

    self.constants[self.constants_count] = value;
    self.constants_count += 1;
    return @intCast(self.constants_count - 1);
}

fn printError(comptime format: []const u8, args: anytype) void {
    const StdErr = std.io.getStdErr().writer();
    StdErr.print(format, args) catch {};
    StdErr.writeByte('\n') catch {};
}
