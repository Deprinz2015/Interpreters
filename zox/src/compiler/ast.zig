const std = @import("std");
const Allocator = std.mem.Allocator;
const Token = @import("Token.zig");

pub const Expr = union(enum) {
    literal: Literal,
    unary: Unary,

    pub fn literal(alloc: Allocator, token: Token, value: std.meta.FieldType(Literal, .value)) !*Expr {
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

    const Literal = struct {
        token: Token,
        value: union(enum) {
            number: f64,
            string: []const u8,
            nil: void,
            boolean: bool,
        },
    };

    const Unary = struct {
        op: Token,
        expr: *Expr,
    };

    pub fn format(value: Expr, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .literal => switch (value.literal.value) {
                .number => |num| try writer.print("{d}", .{num}),
                .string => |str| try writer.print("{s}", .{str}),
                .nil => try writer.writeAll("nil"),
                .boolean => |val| try writer.writeAll(if (val) "true" else "false"),
            },
            .unary => try writer.print("Unary: {s} {}", .{ value.unary.op.lexeme, value.unary.expr.* }),
        }
    }
};

// pub const Statement = union(enum) {};
