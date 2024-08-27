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

    pub fn literal(alloc: Allocator, value: Literal.Value) !*Expr {
        const node = try alloc.create(Expr);
        node.* = .{
            .literal = .{
                .value = value,
            },
        };

        return node;
    }

    pub fn unary(alloc: Allocator, op: Token, expr: *Expr) !*Expr {
        const node = try alloc.create(Expr);
        node.* = .{
            .unary = .{
                .op = op,
                .expr = expr,
            },
        };

        return node;
    }

    pub fn binary(alloc: Allocator, op: Token, left: *Expr, right: *Expr) !*Expr {
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

    pub fn logical(alloc: Allocator, op: Token, left: *Expr, right: *Expr) !*Expr {
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

    pub fn variable(alloc: Allocator, name: Token) !*Expr {
        const node = try alloc.create(Expr);
        node.* = .{
            .variable = .{
                .name = name,
            },
        };
        return node;
    }

    pub fn assignment(alloc: Allocator, name: Token, value: *Expr) !*Expr {
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

    pub fn expression(alloc: Allocator, expr: *Expr) !*Stmt {
        const node = try alloc.create(Stmt);
        node.* = .{
            .expression = .{
                .expr = expr,
            },
        };
        return node;
    }

    pub fn print(alloc: Allocator, expr: *Expr) !*Stmt {
        const node = try alloc.create(Stmt);
        node.* = .{
            .print = .{
                .expr = expr,
            },
        };
        return node;
    }

    pub fn returnStmt(alloc: Allocator, expr: ?*Expr) !*Stmt {
        const node = try alloc.create(Stmt);
        node.* = .{
            .return_stmt = .{
                .expr = expr,
            },
        };
        return node;
    }

    pub fn block(alloc: Allocator, stmts: []*Stmt) !*Stmt {
        const node = try alloc.create(Stmt);
        node.* = .{
            .block = .{
                .stmts = stmts,
            },
        };
        return node;
    }

    pub fn whileStmt(alloc: Allocator, condition: *Expr, statement: *Stmt) !*Stmt {
        const node = try alloc.create(Stmt);
        node.* = .{
            .while_stmt = .{
                .condition = condition,
                .statement = statement,
            },
        };
        return node;
    }

    pub fn ifStmt(alloc: Allocator, condition: *Expr, statement: *Stmt, else_stmt: ?*Stmt) !*Stmt {
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

    pub fn varStmt(alloc: Allocator, name: Token, initializer: ?*Expr) !*Stmt {
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

pub const PrettyPrinter = struct {
    const StdOut = std.io.getStdOut().writer();

    pub fn print(program: []*Stmt) !void {
        for (program) |stmt| {
            try printStmtOnLevel(stmt, 0);
        }
    }

    fn printStmtOnLevel(node: *Stmt, level: u8) !void {
        try StdOut.writeAll("|");
        for (0..level) |_| {
            try StdOut.writeAll(" |");
        }

        try StdOut.writeAll("-");
        switch (node.*) {
            .expression => {
                try StdOut.writeAll("[expression - expr]");
                try StdOut.writeByte('\n');
                try printExprOnLevel(node.expression.expr, level + 1);
            },
            .print => {
                try StdOut.writeAll("[print - expr]");
                try StdOut.writeByte('\n');
                try printExprOnLevel(node.print.expr, level + 1);
            },
            .return_stmt => {
                if (node.return_stmt.expr) |expr| {
                    try StdOut.writeAll("[return - expr]");
                    try StdOut.writeByte('\n');
                    try printExprOnLevel(expr, level + 1);
                } else {
                    try StdOut.writeAll("[return]");
                    try StdOut.writeByte('\n');
                }
            },
            .block => {
                try StdOut.writeAll("[block - stmts[]]");
                try StdOut.writeByte('\n');
                for (node.block.stmts) |stmt| {
                    try printStmtOnLevel(stmt, level + 1);
                }
            },
            .while_stmt => {
                try StdOut.writeAll("[while - condition statement]");
                try StdOut.writeByte('\n');
                try printExprOnLevel(node.while_stmt.condition, level + 1);
                try printStmtOnLevel(node.while_stmt.statement, level + 1);
            },
            .if_stmt => {
                if (node.if_stmt.else_stmt) |_| {
                    try StdOut.writeAll("[if - condition statement statement]");
                } else {
                    try StdOut.writeAll("[if - condition statement]");
                }
                try StdOut.writeByte('\n');
                try printExprOnLevel(node.if_stmt.condition, level + 1);
                try printStmtOnLevel(node.if_stmt.statement, level + 1);
                if (node.if_stmt.else_stmt) |else_stmt| {
                    try printStmtOnLevel(else_stmt, level + 1);
                }
            },
            .var_stmt => {
                try StdOut.print("[var - '{s}' initializer]", .{node.var_stmt.name.lexeme});
                try StdOut.writeByte('\n');
                if (node.var_stmt.initializer) |expr| {
                    try printExprOnLevel(expr, level + 1);
                }
            },
        }
    }

    fn printExprOnLevel(node: *Expr, level: u8) !void {
        try StdOut.writeAll("|");
        for (0..level) |_| {
            try StdOut.writeAll(" |");
        }

        try StdOut.writeAll("-");
        switch (node.*) {
            .literal => {
                try StdOut.print("(literal: {})", .{node.*});
                try StdOut.writeByte('\n');
            },
            .unary => |unary| {
                try StdOut.print("(unary '{s}' - expr)", .{unary.op.lexeme});
                try StdOut.writeByte('\n');
                try printExprOnLevel(unary.expr, level + 1);
            },
            .binary => |binary| {
                try StdOut.print("(binary '{s}' - left, right)", .{binary.op.lexeme});
                try StdOut.writeByte('\n');
                try printExprOnLevel(binary.left, level + 1);
                try printExprOnLevel(binary.right, level + 1);
            },
            .logical => |logical| {
                try StdOut.print("(logical '{s}' - left, right)", .{logical.op.lexeme});
                try StdOut.writeByte('\n');
                try printExprOnLevel(logical.left, level + 1);
                try printExprOnLevel(logical.right, level + 1);
            },
            .variable => |variable| {
                try StdOut.print("(variable: {s})", .{variable.name.lexeme});
                try StdOut.writeByte('\n');
            },
            .assignment => |assign| {
                try StdOut.print("(assignment '{s}' - expr)", .{assign.name.lexeme});
                try StdOut.writeByte('\n');
                try printExprOnLevel(assign.value, level + 1);
            },
        }
    }
};
