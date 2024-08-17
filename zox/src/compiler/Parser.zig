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

pub fn parse(self: *Parser) ?*ast.Expr {
    self.current = self.scanner.nextToken(); // Priming the Parser
    return self.expression() catch null;
}

fn expression(self: *Parser) !*ast.Expr {
    return self.unary();
}

fn unary(self: *Parser) !*ast.Expr {
    if (self.match(.@"-") or self.match(.@"!")) {
        return ast.Expr.unary(self.alloc.allocator(), self.previous.?, try self.unary());
    }

    return self.primary();
}

fn primary(self: *Parser) !*ast.Expr {
    switch (self.current.type) {
        .FALSE => return ast.Expr.literal(self.alloc.allocator(), self.current, .{ .boolean = false }),
        .TRUE => return ast.Expr.literal(self.alloc.allocator(), self.current, .{ .boolean = true }),
        .NIL => return ast.Expr.literal(self.alloc.allocator(), self.current, .nil),
        .STRING => {
            const string = self.current.lexeme[1 .. self.current.lexeme.len - 1];
            return ast.Expr.literal(self.alloc.allocator(), self.current, .{ .string = string });
        },
        .NUMBER => {
            const number = std.fmt.parseFloat(f64, self.current.lexeme) catch {
                printError("'{s}' is not a number", .{self.current.lexeme});
                return Error.WrongNumberFormat;
            };
            return ast.Expr.literal(self.alloc.allocator(), self.current, .{ .number = number });
        },
        else => {
            printError("Expected Expression", .{});
            return Error.MissingExpression;
        },
    }
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

fn consume(self: *Parser, t_type: Token.Type, msg: []const u8) !void {
    if (self.check(t_type)) {
        self.advance();
    }

    printError(msg, .{});
    return Error.WrongTokenType;
}

fn printError(comptime format: []const u8, args: anytype) void {
    StdErr.writer().print(format, args) catch {};
    StdErr.writeAll("\n") catch {};
}
