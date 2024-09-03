const std = @import("std");
const Allocator = std.mem.Allocator;
const Token = @import("Token.zig");

pub const Expr = union(enum) {
    literal: Literal,
    unary: Unary,
    binary: Binary,
    logical: Logical,
    variable: Variable,
    assignment: Assignment,

    pub fn newLiteral(alloc: Allocator, value: Literal.Value) !*Expr {
        const node = try alloc.create(Expr);
        node.* = .{
            .literal = .{
                .value = value,
            },
        };

        return node;
    }

    pub fn newUnary(alloc: Allocator, op: Token, expr: *Expr) !*Expr {
        const node = try alloc.create(Expr);
        node.* = .{
            .unary = .{
                .op = op,
                .expr = expr,
            },
        };

        return node;
    }

    pub fn newBinary(alloc: Allocator, op: Token, left: *Expr, right: *Expr) !*Expr {
        const node = try alloc.create(Expr);
        node.* = .{
            .binary = .{
                .op = op,
                .left = left,
                .right = right,
            },
        };

        return node;
    }

    pub fn newLogical(alloc: Allocator, op: Token, left: *Expr, right: *Expr) !*Expr {
        const node = try alloc.create(Expr);
        node.* = .{
            .logical = .{
                .op = op,
                .left = left,
                .right = right,
            },
        };

        return node;
    }

    pub fn newVariable(alloc: Allocator, name: Token) !*Expr {
        const node = try alloc.create(Expr);
        node.* = .{
            .variable = .{
                .name = name,
            },
        };
        return node;
    }

    pub fn newAssignment(alloc: Allocator, name: Token, value: *Expr) !*Expr {
        const node = try alloc.create(Expr);
        node.* = .{
            .assignment = .{
                .name = name,
                .value = value,
            },
        };

        return node;
    }

    pub const Literal = struct {
        value: Value,

        pub const Value = union(enum) {
            number: f64,
            string: []const u8,
            nil: void,
            boolean: bool,
        };
    };

    pub const Unary = struct {
        op: Token,
        expr: *Expr,
    };

    pub const Binary = struct {
        op: Token,
        left: *Expr,
        right: *Expr,
    };

    pub const Logical = struct {
        op: Token,
        left: *Expr,
        right: *Expr,
    };

    pub const Variable = struct {
        name: Token,
    };

    pub const Assignment = struct {
        name: Token,
        value: *Expr,
    };

    pub fn format(value: Expr, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .literal => switch (value.literal.value) {
                .number => |num| try writer.print("{d}", .{num}),
                .string => |str| try writer.print("{s}", .{str}),
                .nil => try writer.writeAll("nil"),
                .boolean => |val| try writer.writeAll(if (val) "true" else "false"),
            },
            .unary => try writer.print("Unary: {s} expr", .{value.unary.op.lexeme}),
            .binary => try writer.print("Binary: {s}", .{value.binary.op.lexeme}),
            .logical => try writer.print("Logical: {s}", .{value.logical.op.lexeme}),
            .assignment => try writer.print("Assignment: {s} expr", .{value.assignment.name.lexeme}),
            .variable => try writer.print("Variable: {s}", .{value.variable.name.lexeme}),
        }
    }
};

pub const Stmt = union(enum) {
    expression: Expression,
    print: Print,
    return_stmt: Return,
    block: Block,
    while_stmt: While,
    if_stmt: If,
    var_stmt: Var,

    pub fn newExpression(alloc: Allocator, expr: *Expr) !*Stmt {
        const node = try alloc.create(Stmt);
        node.* = .{
            .expression = .{
                .expr = expr,
            },
        };
        return node;
    }

    pub fn newPrint(alloc: Allocator, expr: *Expr) !*Stmt {
        const node = try alloc.create(Stmt);
        node.* = .{
            .print = .{
                .expr = expr,
            },
        };
        return node;
    }

    pub fn newReturn(alloc: Allocator, expr: ?*Expr) !*Stmt {
        const node = try alloc.create(Stmt);
        node.* = .{
            .return_stmt = .{
                .expr = expr,
            },
        };
        return node;
    }

    pub fn newBlock(alloc: Allocator, stmts: []*Stmt) !*Stmt {
        const node = try alloc.create(Stmt);
        node.* = .{
            .block = .{
                .stmts = stmts,
            },
        };
        return node;
    }

    pub fn newWhile(alloc: Allocator, condition: *Expr, statement: *Stmt) !*Stmt {
        const node = try alloc.create(Stmt);
        node.* = .{
            .while_stmt = .{
                .condition = condition,
                .statement = statement,
            },
        };
        return node;
    }

    pub fn newIf(alloc: Allocator, condition: *Expr, statement: *Stmt, else_stmt: ?*Stmt) !*Stmt {
        const node = try alloc.create(Stmt);
        node.* = .{
            .if_stmt = .{
                .condition = condition,
                .statement = statement,
                .else_stmt = else_stmt,
            },
        };
        return node;
    }

    pub fn newVar(alloc: Allocator, name: Token, initializer: ?*Expr) !*Stmt {
        const node = try alloc.create(Stmt);
        node.* = .{
            .var_stmt = .{
                .name = name,
                .initializer = initializer,
            },
        };
        return node;
    }

    pub const Expression = struct {
        expr: *Expr,
    };

    pub const Print = struct {
        expr: *Expr,
    };

    pub const Return = struct {
        expr: ?*Expr,
    };

    pub const Block = struct {
        stmts: []*Stmt,
    };

    pub const While = struct {
        condition: *Expr,
        statement: *Stmt,
    };

    pub const If = struct {
        condition: *Expr,
        statement: *Stmt,
        else_stmt: ?*Stmt,
    };

    pub const Var = struct {
        name: Token,
        initializer: ?*Expr,
    };

    pub fn format(value: Stmt, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .expression => try writer.writeAll("Expression: expr"),
            .print => try writer.writeAll("Print: expr"),
            .block => try writer.writeAll("Block: stmts[]"),
            .while_stmt => try writer.writeAll("While: expr stmt"),
            .return_stmt => try writer.writeAll("Return: ?expr"),
        }
    }
};
