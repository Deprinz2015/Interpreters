const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");
const Instruction = @import("../instruction_set.zig").Instruction;
const Value = @import("value.zig").Value;

const Compiler = @This();

const FunctionEntry = struct {
    arity: u8,
    name: u8, // Index of Constant
    code: []u8,
};

code: std.ArrayList(u8),
constants: [256]Value = undefined, // Max 256 constants are allowed
constants_count: usize = 0,
functions: std.ArrayList(FunctionEntry),
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
    const UpvalueEntry = struct {
        local_idx: u8,
        name: []const u8,
    };

    code: std.ArrayList(u8),
    compiler: *Compiler,
    locals: [256][]const u8,
    locals_count: usize,
    upvalues: [256]UpvalueEntry,
    upvalues_count: usize,
    enclosing: ?*TreeWalker,

    fn init(compiler: *Compiler, enclosing: ?*TreeWalker) TreeWalker {
        return .{
            .compiler = compiler,
            .code = .init(compiler.alloc),
            .locals = undefined,
            .locals_count = 0,
            .upvalues = undefined,
            .upvalues_count = 0,
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
                    const name: Value = .{ .string = decl.name.lexeme };
                    const idx = self.compiler.saveConstant(name) catch {
                        self.compiler.printError("Could not save constant string '{s}'", .{name.string});
                        return;
                    };
                    self.writeOperand(.GLOBAL_DEFINE, idx);
                } else {
                    self.locals[self.locals_count] = decl.name.lexeme;
                    self.locals_count += 1;
                    self.writeOp(.LOCAL_DEFINE);
                }
            },
            .block => |block| {
                const code = self.traverseBlock(block.stmts);
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
            .return_stmt => |return_stmt| {
                if (return_stmt.expr) |expr| {
                    self.traverseExpression(expr);
                } else {
                    self.writeOp(.NIL);
                }

                self.writeOp(.RETURN);
            },
            .function => |function| {
                for (function.params) |param| {
                    self.locals[self.locals_count] = param.lexeme;
                    self.locals_count += 1;
                }

                std.debug.print("closure: {}\n", .{self.enclosing != null});
                const code = self.traverseBlock(function.body);

                if (self.enclosing == null) {
                    const name_str: Value = .{ .string = function.name.lexeme };
                    const name = self.compiler.saveConstant(name_str) catch {
                        self.compiler.printError("Could not save constant string '{s}'", .{function.name.lexeme});
                        return;
                    };
                    self.compiler.saveFunction(code, @intCast(function.params.len), name) catch self.compiler.printError("Could not save function '{s}'", .{function.name.lexeme});
                } else {
                    self.writeOperand(.CLOSURE_START, @intCast(function.params.len));
                    for (self.upvalues, 0..) |upvalue, i| {
                        if (i >= self.upvalues_count) {
                            break;
                        }

                        self.writeOperand(.UPVALUE_DEFINE, upvalue.local_idx);
                    }
                    self.writeOp(.UPVALUE_DONE);
                    self.code.appendSlice(code) catch @panic("Out of Memory");
                    self.compiler.alloc.free(code);
                    self.writeOp(.CLOSURE_END);
                }
            },
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
                .boolean => |b| self.writeOp(if (b) .TRUE else .FALSE),
                .nil => self.writeOp(.NIL),
                .number => |num| {
                    const idx = self.compiler.saveConstant(.{ .number = num }) catch {
                        self.compiler.printError("Could not save constant number '{d}'", .{num});
                        return;
                    };
                    self.writeOperand(.CONSTANT, idx);
                },
                .string => |str| {
                    const string: Value = .{ .string = str };
                    const idx = self.compiler.saveConstant(string) catch {
                        self.compiler.printError("Could not save constant string '{s}'", .{str});
                        return;
                    };
                    self.writeOperand(.CONSTANT, idx);
                },
            },
            .variable => |variable| if (self.resolveVariabe(variable.name.lexeme)) |result| {
                switch (result.type) {
                    .LOCAL => self.writeOperand(.LOCAL_GET, result.idx),
                    .GLOBAL => self.writeOperand(.GLOBAL_GET, result.idx),
                    .UPVALUE => self.writeOperand(.UPVALUE_GET, result.idx),
                }
            },
            .assignment => |assignment| {
                self.traverseExpression(assignment.value);
                if (self.resolveVariabe(assignment.name.lexeme)) |result| {
                    switch (result.type) {
                        .LOCAL => self.writeOperand(.LOCAL_SET, result.idx),
                        .GLOBAL => self.writeOperand(.GLOBAL_SET, result.idx),
                        .UPVALUE => self.writeOperand(.UPVALUE_SET, result.idx),
                    }
                }
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

    fn traverseBlock(self: *TreeWalker, stmts: []*ast.Stmt) []u8 {
        var walker: TreeWalker = .init(self.compiler, self);
        defer walker.code.deinit();

        for (stmts) |statement| {
            walker.traverseStatement(statement);
        }

        for (0..walker.locals_count) |_| {
            walker.writeOp(.LOCAL_POP);
        }

        return walker.code.toOwnedSlice() catch @panic("Out of Memory");
    }

    fn resolveAssign(self: *TreeWalker, string: []const u8) void {
        if (self.enclosing != null) {
            // 1. search for local
            // 2. search for existing upvalue
            // 3. search upwards for locals and turn them into upvalue

            // 1.
            if (self.getLocalIdx(string)) |idx| {
                self.writeOperand(.LOCAL_SET_AT, idx);
                return;
            }

            //                              2.                               3.
            const maybe_upvalue = self.getUpvalueIdx(string) orelse self.findNewUpvalue(string);
            if (maybe_upvalue) |idx| {
                self.writeOperand(.UPVALUE_GET, idx);
                return;
            }
        }
        // Global scope or no local/upvalue found
        const name: Value = .{ .string = string };
        const idx = self.compiler.saveConstant(name) catch {
            printError("Could not save constant string '{s}'", .{name.string});
            self.compiler.has_error = true;
            return;
        };
        self.writeOperand(.GLOBAL_GET, idx);
    }

    fn resolveVariabe(self: *TreeWalker, string: []const u8) ?struct {
        type: enum { LOCAL, GLOBAL, UPVALUE },
        idx: u8,
    } {
        if (self.enclosing != null) {
            // 1. search for local
            // 2. search for existing upvalue
            // 3. search upwards for locals and turn them into upvalue

            std.debug.print("searching for {s}\n", .{string});
            // 1.
            if (self.getLocalIdx(string)) |idx| {
                std.debug.print("found local {s} at {d}\n", .{ string, idx });
                return .{ .type = .LOCAL, .idx = idx };
            }

            //                              2.                               3.
            const maybe_upvalue = self.getUpvalueIdx(string) orelse self.findNewUpvalue(string);
            if (maybe_upvalue) |idx| {
                return .{ .type = .UPVALUE, .idx = idx };
            }
        }
        // Global scope or no local/upvalue found
        const name: Value = .{ .string = string };
        const idx = self.compiler.saveConstant(name) catch {
            self.compiler.printError("Could not save constant string '{s}'", .{name.string});
            return null;
        };
        return .{ .type = .GLOBAL, .idx = idx };
    }

    fn getLocalIdx(self: *TreeWalker, name: []const u8) ?u8 {
        for (self.locals, 0..) |local, i| {
            if (i >= self.locals_count) {
                break;
            }
            if (std.mem.eql(u8, local, name)) {
                return @intCast(self.locals_count - i);
            }
        }
        return 0;
    }

    fn getUpvalueIdx(self: *TreeWalker, name: []const u8) ?u8 {
        for (self.upvalues, 0..) |upvalue, i| {
            if (i >= self.upvalues_count) {
                break;
            }
            if (std.mem.eql(u8, upvalue.name, name)) {
                return @intCast(self.upvalues_count - i);
            }
        }
        return null;
    }

    fn findNewUpvalue(self: *TreeWalker, name: []const u8) ?u8 {
        if (self.enclosing == null) {
            return null; // This should not even happen
        }

        if (self.resolveLocal(name)) |idx| {
            self.upvalues[self.upvalues_count] = .{ .local_idx = idx, .name = name };
            self.upvalues_count += 1;
            return @intCast(self.upvalues_count - 1);
        }

        return null;
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
            self.compiler.printError("Too much code to jump: {d}", .{idx});
        }

        self.writeOp(jump);
        self.writeByte(@intCast((idx >> 8) & 0xff));
        self.writeByte(@intCast(idx & 0xff));
    }

    fn patchJump(self: *TreeWalker, jump_idx: usize) void {
        const jump = self.code.items.len - jump_idx - 2;

        if (jump > std.math.maxInt(u16)) {
            self.compiler.printError("Too much code to jump: {d}", .{jump});
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
        .functions = .init(alloc),
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
    self.functions.deinit();
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

    try self.insertFunctions();
    try self.insertConstants();
}

fn toBytecode(self: *Compiler) ![]u8 {
    return try self.code.toOwnedSlice();
}

fn insertFunctions(self: *Compiler) !void {
    var functions_code: std.ArrayList(u8) = .init(self.alloc);
    defer functions_code.deinit();

    for (self.functions.items) |function| {
        try functions_code.append(@intFromEnum(Instruction.FUNCTION_START));
        try functions_code.append(function.name);
        try functions_code.append(function.arity);
        try functions_code.appendSlice(function.code);
        self.alloc.free(function.code);
    }

    try functions_code.append(@intFromEnum(Instruction.FUNCTIONS_DONE));
    const functions_raw = try functions_code.toOwnedSlice();
    defer self.alloc.free(functions_raw);

    try self.code.insertSlice(0, functions_raw);
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

fn saveFunction(self: *Compiler, code: []u8, arity: u8, name: u8) !void {
    try self.functions.append(.{ .code = code, .arity = arity, .name = name });
}

fn printError(self: *Compiler, comptime format: []const u8, args: anytype) void {
    const StdErr = std.io.getStdErr().writer();
    StdErr.print(format, args) catch {};
    StdErr.writeByte('\n') catch {};
    self.has_error = true;
}
