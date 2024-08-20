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

pub fn init(alloc: Allocator, scanner: *Scanner) Parser {
    return .{
        .scanner = scanner,
        .current = undefined,
        .previous = null,
        .alloc = std.heap.ArenaAllocator.init(alloc),
    };
}

/// All created nodes will be deinited, make sure to copy them if longer lifetime is needed
pub fn deinit(self: *Parser) void {
    self.alloc.deinit();
}

pub fn parse(self: *Parser) ?[]*ast.Stmt {
    self.current = self.scanner.nextToken(); // Priming the Parser

    var statements = std.ArrayList(*ast.Stmt).init(self.alloc.allocator());

    while (!self.atEnd()) {
        const stmt = self.statement() catch return null;
        statements.append(stmt) catch return null;
    }

    return statements.toOwnedSlice() catch null;
}

fn statement(self: *Parser) Error!*ast.Stmt {
    if (self.match(.PRINT)) {
        return self.printStatement();
    }

    return self.expressionStatement();
}

fn printStatement(self: *Parser) Error!*ast.Stmt {
    const expr = try self.expression();
    try self.consume(.@";", "Expected ';' after expression");
    return ast.Stmt.print(self.alloc.allocator(), expr) catch Error.CouldNotGenerateNode;
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

fn sync(self: *Parser) Error!void {
    self.advance();

    while (!self.atEnd()) {
        if (self.previous == .@";") {
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
    return ast.Expr.literal(self.alloc.allocator(), self.previous.?, value) catch Error.CouldNotGenerateNode;
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
