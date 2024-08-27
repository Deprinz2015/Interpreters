const std = @import("std");
const Allocator = std.mem.Allocator;
const StdErr = std.io.getStdErr();

const Scanner = @import("Scanner.zig");
const Token = @import("Token.zig");
const ast = @import("ast.zig");

const Parser = @This();

const Error = error{
    UnexpectedToken,
    MissingExpression,
    WrongNumberFormat,
    CouldNotGenerateNode,
    InvalidAssignment,
};

scanner: *Scanner,
current: Token,
previous: ?Token,
alloc: std.heap.ArenaAllocator,
has_error: bool,

pub fn init(alloc: Allocator, scanner: *Scanner) Parser {
    return .{
        .scanner = scanner,
        .current = undefined,
        .previous = null,
        .alloc = std.heap.ArenaAllocator.init(alloc),
        .has_error = false,
    };
}

/// All created nodes will be deinited, make sure to copy them if longer lifetime is needed
pub fn deinit(self: *Parser) void {
    self.alloc.deinit();
}

pub fn parse(self: *Parser) ?[]*ast.Stmt {
    self.current = self.scanner.nextToken(); // Priming the Parser

    var statements = std.ArrayList(*ast.Stmt).init(self.alloc.allocator());
    defer statements.deinit();

    while (!self.atEnd()) {
        const maybe_stmt = self.decl();
        if (maybe_stmt) |stmt| {
            statements.append(stmt) catch return null;
        }
    }

    if (self.has_error) {
        return null;
    }
    return statements.toOwnedSlice() catch null;
}

fn decl(self: *Parser) ?*ast.Stmt {
    return self.declaration() catch {
        self.sync();
        self.has_error = true;
        return null;
    };
}

fn declaration(self: *Parser) !*ast.Stmt {
    if (self.match(.VAR)) {
        return self.varDeclaration();
    }

    return self.statement();
}

fn varDeclaration(self: *Parser) !*ast.Stmt {
    try self.consume(.IDENTIFIER, "Expect variable name");
    const name = self.previous.?;

    const initializer: ?*ast.Expr = expr: {
        if (self.match(.@"=")) {
            break :expr try self.expression();
        }
        break :expr null;
    };

    try self.consume(.@";", "Expect ';' after variable declaration");

    return ast.Stmt.varStmt(self.alloc.allocator(), name, initializer) catch Error.CouldNotGenerateNode;
}

fn statement(self: *Parser) Error!*ast.Stmt {
    if (self.match(.PRINT)) {
        return self.printStatement();
    }

    if (self.match(.RETURN)) {
        return self.returnStatement();
    }

    if (self.match(.WHILE)) {
        return self.whileStatement();
    }

    if (self.match(.IF)) {
        return self.ifStatement();
    }

    if (self.match(.FOR)) {
        return self.forStatement();
    }

    if (self.match(.@"{")) {
        var statements = std.ArrayList(*ast.Stmt).init(self.alloc.allocator());

        while (!self.atEnd() and !self.check(.@"}")) {
            const maybe_stmt = self.decl();
            if (maybe_stmt) |stmt| {
                statements.append(stmt) catch return Error.CouldNotGenerateNode;
            }
        }

        try self.consume(.@"}", "Expected '}}' after block");
        const stmts = statements.toOwnedSlice() catch return Error.CouldNotGenerateNode;
        return ast.Stmt.block(self.alloc.allocator(), stmts) catch Error.CouldNotGenerateNode;
    }

    return self.expressionStatement();
}

fn forStatement(self: *Parser) Error!*ast.Stmt {
    try self.consume(.@"(", "Expected '(' after for keyword");

    const initializer: ?*ast.Stmt = init: {
        if (self.match(.@";")) {
            break :init null;
        }

        if (self.match(.VAR)) {
            break :init try self.varDeclaration();
        }

        break :init try self.expressionStatement();
    };

    const condition: *ast.Expr = condition: {
        if (self.check(.@";")) {
            break :condition ast.Expr.literal(self.alloc.allocator(), .{ .boolean = true }) catch return Error.CouldNotGenerateNode;
        }
        break :condition try self.expression();
    };

    try self.consume(.@";", "Expected ';' after loop condition");

    const increment: ?*ast.Stmt = inc: {
        if (self.check(.@")")) {
            break :inc null;
        }
        const expr = try self.expression();
        break :inc ast.Stmt.expression(self.alloc.allocator(), expr) catch return Error.CouldNotGenerateNode;
    };

    try self.consume(.@")", "Expected ')' after increment");
    const body = try self.statement();

    if (increment) |inc_expr| {
        body.block.stmts = self.alloc.allocator().realloc(body.block.stmts, body.block.stmts.len + 1) catch return Error.CouldNotGenerateNode;
        body.block.stmts[body.block.stmts.len - 1] = inc_expr;
    }

    const while_stmt = ast.Stmt.whileStmt(self.alloc.allocator(), condition, body) catch return Error.CouldNotGenerateNode;

    if (initializer) |init_stmt| {
        const stmts = self.alloc.allocator().alloc(*ast.Stmt, 2) catch return Error.CouldNotGenerateNode;
        stmts[0] = init_stmt;
        stmts[1] = while_stmt;
        return ast.Stmt.block(self.alloc.allocator(), stmts) catch Error.CouldNotGenerateNode;
    }

    return while_stmt;
}

fn printStatement(self: *Parser) Error!*ast.Stmt {
    const expr = try self.expression();
    try self.consume(.@";", "Expected ';' after expression");
    return ast.Stmt.print(self.alloc.allocator(), expr) catch Error.CouldNotGenerateNode;
}

fn returnStatement(self: *Parser) Error!*ast.Stmt {
    if (self.match(.@";")) {
        return ast.Stmt.returnStmt(self.alloc.allocator(), null) catch Error.CouldNotGenerateNode;
    }

    const expr = try self.expression();
    try self.consume(.@";", "Expected ';' after expression");
    return ast.Stmt.returnStmt(self.alloc.allocator(), expr) catch Error.CouldNotGenerateNode;
}

fn whileStatement(self: *Parser) Error!*ast.Stmt {
    try self.consume(.@"(", "Expected '(' after while keyword");
    const condition = try self.expression();
    try self.consume(.@")", "Expected ')' after while condition");
    const stmt = try self.statement();
    return ast.Stmt.whileStmt(self.alloc.allocator(), condition, stmt) catch Error.CouldNotGenerateNode;
}

fn ifStatement(self: *Parser) Error!*ast.Stmt {
    try self.consume(.@"(", "Expected '(' after if keyword");
    const condition = try self.expression();
    try self.consume(.@")", "Expected ')' after if condition");
    const stmt = try self.statement();
    if (self.match(.ELSE)) {
        const else_stmt = try self.statement();
        return ast.Stmt.ifStmt(self.alloc.allocator(), condition, stmt, else_stmt) catch Error.CouldNotGenerateNode;
    }
    return ast.Stmt.ifStmt(self.alloc.allocator(), condition, stmt, null) catch Error.CouldNotGenerateNode;
}

fn expressionStatement(self: *Parser) Error!*ast.Stmt {
    const expr = try self.expression();
    try self.consume(.@";", "Expected ';' after expression");
    return ast.Stmt.expression(self.alloc.allocator(), expr) catch Error.CouldNotGenerateNode;
}

fn expression(self: *Parser) Error!*ast.Expr {
    return self.assignment();
}

fn assignment(self: *Parser) Error!*ast.Expr {
    const expr = try self.logical_or();
    if (self.match(.@"=")) {
        if (expr.* == .variable) {
            const value = try self.expression();
            return ast.Expr.assignment(self.alloc.allocator(), expr.variable.name, value) catch Error.CouldNotGenerateNode;
        }

        printError("Invalid assignment target", .{});
        return Error.InvalidAssignment;
    }

    return expr;
}

fn logical_or(self: *Parser) Error!*ast.Expr {
    var left = try self.logical_and();
    while (self.match(.OR)) {
        const op = self.previous.?;
        const right = try self.logical_and();
        left = try self.logical(op, left, right);
    }

    return left;
}

fn logical_and(self: *Parser) Error!*ast.Expr {
    var left = try self.equality();
    while (self.match(.AND)) {
        const op = self.previous.?;
        const right = try self.equality();
        left = try self.logical(op, left, right);
    }

    return left;
}

fn equality(self: *Parser) Error!*ast.Expr {
    var left = try self.comparison();
    while (self.match(.@"==") or self.match(.@"!=")) {
        const op = self.previous.?;
        const right = try self.comparison();
        left = try self.binary(op, left, right);
    }

    return left;
}

fn comparison(self: *Parser) Error!*ast.Expr {
    var left = try self.term();
    while (self.match(.@"<") or self.match(.@"<=") or self.match(.@">") or self.match(.@">=")) {
        const op = self.previous.?;
        const right = try self.term();
        left = try self.binary(op, left, right);
    }
    return left;
}

fn term(self: *Parser) Error!*ast.Expr {
    var left = try self.factor();
    while (self.match(.@"+") or self.match(.@"-")) {
        const op = self.previous.?;
        const right = try self.factor();
        left = try self.binary(op, left, right);
    }

    return left;
}

fn factor(self: *Parser) Error!*ast.Expr {
    var left = try self.unary();
    while (self.match(.@"/") or self.match(.@"*")) {
        const op = self.previous.?;
        const right = try self.unary();
        left = try self.binary(op, left, right);
    }

    return left;
}

fn unary(self: *Parser) Error!*ast.Expr {
    if (self.match(.@"-") or self.match(.@"!")) {
        return ast.Expr.unary(self.alloc.allocator(), self.previous.?, try self.unary()) catch Error.CouldNotGenerateNode;
    }

    return self.primary();
}

// TODO: Add a call expression between unary and primary
// unary   → ( "!" | "-" ) unary | call ;
// call    → primary ( "(" arguments? ")" )* ;

fn primary(self: *Parser) Error!*ast.Expr {
    if (self.match(.FALSE)) {
        return self.literal(.{ .boolean = false });
    }
    if (self.match(.TRUE)) {
        return self.literal(.{ .boolean = true });
    }
    if (self.match(.NIL)) {
        return self.literal(.nil);
    }
    if (self.match(.STRING)) {
        const prev_string = self.previousLexeme().?;
        const string = prev_string[1 .. prev_string.len - 1];
        return self.literal(.{ .string = string });
    }
    if (self.match(.NUMBER)) {
        const number = std.fmt.parseFloat(f64, self.previousLexeme().?) catch {
            printError("'{s}' is not a number", .{self.previousLexeme().?});
            return Error.WrongNumberFormat;
        };
        return self.literal(.{ .number = number });
    }
    if (self.match(.IDENTIFIER)) {
        return ast.Expr.variable(self.alloc.allocator(), self.previous.?) catch Error.CouldNotGenerateNode;
    }
    if (self.match(.@"(")) {
        const expr = try self.expression();
        try self.consume(.@")", "Expect ')' after expression");
        return expr;
    }

    printError("Expected Expression", .{});
    return Error.MissingExpression;
}

fn sync(self: *Parser) void {
    self.advance();

    while (!self.atEnd()) {
        if (self.previous != null and self.previous.?.type == .@";") {
            return;
        }

        switch (self.current.type) {
            .FUN,
            .VAR,
            .IF,
            .FOR,
            .WHILE,
            .RETURN,
            .PRINT,
            => return,
            else => self.advance(),
        }
    }
}

fn literal(self: *Parser, value: ast.Expr.Literal.Value) Error!*ast.Expr {
    return ast.Expr.literal(self.alloc.allocator(), value) catch Error.CouldNotGenerateNode;
}

fn binary(self: *Parser, op: Token, left: *ast.Expr, right: *ast.Expr) Error!*ast.Expr {
    return ast.Expr.binary(self.alloc.allocator(), op, left, right) catch return Error.CouldNotGenerateNode;
}

fn logical(self: *Parser, op: Token, left: *ast.Expr, right: *ast.Expr) Error!*ast.Expr {
    return ast.Expr.logical(self.alloc.allocator(), op, left, right) catch return Error.CouldNotGenerateNode;
}

fn advance(self: *Parser) void {
    self.previous = self.current;
    self.current = self.scanner.nextToken();
}

fn check(self: *Parser, t_type: Token.Type) bool {
    return self.current.type == t_type;
}

fn match(self: *Parser, t_type: Token.Type) bool {
    if (self.check(t_type)) {
        self.advance();
        return true;
    }
    return false;
}

fn consume(self: *Parser, t_type: Token.Type, comptime msg: []const u8) Error!void {
    if (self.check(t_type)) {
        self.advance();
        return;
    }

    printError(msg, .{});
    return Error.UnexpectedToken;
}

fn atEnd(self: *Parser) bool {
    return self.check(.EOF);
}

fn currentLexeme(self: *Parser) []const u8 {
    return self.current.lexeme;
}

fn previousLexeme(self: *Parser) ?[]const u8 {
    if (self.previous) |prev| {
        return prev.lexeme;
    }
    return null;
}

fn printError(comptime format: []const u8, args: anytype) void {
    StdErr.writer().print(format, args) catch {};
    StdErr.writeAll("\n") catch {};
}
