const std = @import("std");
const ast = @import("../compiler/ast.zig");

const Stmt = ast.Stmt;
const Expr = ast.Expr;

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
