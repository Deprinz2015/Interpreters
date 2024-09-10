const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");
const Token = @import("Token.zig");

pub const Scoping = struct {
    alloc: Allocator,
    tree: []*ast.Stmt,
    scopes: std.ArrayList(std.StringHashMap(bool)),

    const Error = error{
        UnterminatedScopes,
        AccessBeforeDefined,
    };

    pub fn init(alloc: Allocator, tree: []*ast.Stmt) Scoping {
        return .{
            .alloc = alloc,
            .tree = tree,
            .scopes = .init(alloc),
        };
    }

    pub fn deinit(self: *Scoping) void {
        for (0..self.scopes.items.len) |i| {
            self.scopes.items[i].deinit();
        }
        self.scopes.deinit();
    }

    pub fn analyse(self: *Scoping) !void {
        for (self.tree) |stmt| {
            try self.visitStmt(stmt);
        }
        if (self.scopes.items.len > 0) {
            return Scoping.Error.UnterminatedScopes;
        }
    }

    fn visitStmt(self: *Scoping, stmt: *ast.Stmt) !void {
        switch (stmt.*) {
            .expression => |expr| try self.visitExpr(expr.expr),
            .print => |print| try self.visitExpr(print.expr),
            .var_stmt => |var_stmt| {
                try self.declare(var_stmt.name);
                if (var_stmt.initializer) |expr| {
                    try self.visitExpr(expr);
                }
                try self.define(var_stmt.name);
            },
            .block => |block| {
                try self.beginScope();
                for (block.stmts) |statement| {
                    try self.visitStmt(statement);
                }
                try self.endScope();
            },
            .return_stmt => |ret| if (ret.expr) |expr| try self.visitExpr(expr),
            .while_stmt => |while_stmt| {
                try self.visitExpr(while_stmt.condition);
                try self.visitStmt(while_stmt.statement);
            },
            .if_stmt => |if_stmt| {
                try self.visitExpr(if_stmt.condition);
                try self.visitStmt(if_stmt.statement);
                if (if_stmt.else_stmt) |else_stmt| {
                    try self.visitStmt(else_stmt);
                }
            },
            .function => |function| {
                try self.declare(function.name);
                try self.define(function.name);

                try self.beginScope();

                for (function.params) |param| {
                    try self.declare(param);
                    try self.define(param);
                }

                for (function.body) |statement| {
                    try self.visitStmt(statement);
                }

                try self.endScope();
            },
        }
    }

    fn visitExpr(self: *Scoping, expr: *ast.Expr) !void {
        switch (expr.*) {
            .literal => {},
            .unary => |unary| try self.visitExpr(unary.expr),
            .assignment => |assignment| try self.visitExpr(assignment.value),
            .binary => |binary| {
                try self.visitExpr(binary.left);
                try self.visitExpr(binary.right);
            },
            .logical => |logical| {
                try self.visitExpr(logical.left);
                try self.visitExpr(logical.right);
            },
            .variable => |variable| {
                for (self.scopes.items) |scope| {
                    if (scope.get(variable.name.lexeme)) |defined| {
                        if (!defined) {
                            // TODO: Better Error message
                            return Scoping.Error.AccessBeforeDefined;
                        }
                    }
                }
            },
            .call => |call| {
                try self.visitExpr(call.callee);
                for (call.arguments) |arg| {
                    try self.visitExpr(arg);
                }
            },
        }
    }

    fn declare(self: *Scoping, name: Token) !void {
        if (self.scopes.items.len == 0) {
            return;
        }

        var scope = self.scopes.pop();
        try scope.put(name.lexeme, false);
        try self.scopes.append(scope);
    }

    fn define(self: *Scoping, name: Token) !void {
        if (self.scopes.items.len == 0) {
            return;
        }

        var scope = self.scopes.pop();
        try scope.put(name.lexeme, true);
        try self.scopes.append(scope);
    }

    fn beginScope(self: *Scoping) !void {
        try self.scopes.append(.init(self.alloc));
    }

    fn endScope(self: *Scoping) !void {
        var scope = self.scopes.pop();
        scope.deinit();
    }
};
// TODO: Globals analyses
// Remember which variables are not locals and the access tries.
// Print every identifier, that is not defined

// TODO: Arity
// In every call expression, if it is statically known, ie a simple identifier,
// Check for the existing function and check the arity
// Check native functions, as well as user space functions
