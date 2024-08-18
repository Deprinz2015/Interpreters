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

    pub fn literal(alloc: Allocator, token: Token, value: Literal.Value) !*Expr {
        const node = try alloc.create(Expr);
        node.* = .{
            .literal = .{
                .token = token,
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
        token: Token,
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

pub const PrettyPrinter = struct {
    const StdOut = std.io.getStdOut().writer();

    pub fn print(root: *Expr) !void {
        try printExprOnLevel(root, 0);
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

// pub const Statement = union(enum) {};
