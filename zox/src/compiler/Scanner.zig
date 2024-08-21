const std = @import("std");
const Token = @import("Token.zig");

const Scanner = @This();

const Keywords = std.StaticStringMap(Token.Type).initComptime(&.{
    .{ "and", .AND },
    .{ "else", .ELSE },
    .{ "false", .FALSE },
    .{ "for", .FOR },
    .{ "fun", .FUN },
    .{ "if", .IF },
    .{ "nil", .NIL },
    .{ "or", .OR },
    .{ "print", .PRINT },
    .{ "return", .RETURN },
    .{ "true", .TRUE },
    .{ "var", .VAR },
    .{ "while", .WHILE },
});

source: []const u8,
current: usize,
start: usize,
line: usize,

pub fn init(source: []const u8) Scanner {
    return .{
        .source = source,
        .current = 0,
        .start = 0,
        .line = 1,
    };
}

pub fn nextToken(self: *Scanner) Token {
    self.skipWhitespaceAndComment();
    self.start = self.current;

    if (self.isAtEnd()) {
        return .{
            .type = .EOF,
            .line = self.line,
            .lexeme = "",
        };
    }

    const c = self.source[self.current];
    self.advance();

    // Tokens with unknown amount of characters
    if (std.ascii.isDigit(c)) {
        return self.number();
    }

    if (c == '"') {
        return self.string();
    }

    if (std.ascii.isAlphabetic(c) or c == '_') {
        return self.identifier();
    }

    // Tokens with 1 or 2 characters and Error
    const t_type: Token.Type = switch (c) {
        '(' => .@"(",
        ')' => .@")",
        '{' => .@"{",
        '}' => .@"}",
        ',' => .@",",
        ';' => .@";",
        '+' => .@"+",
        '-' => .@"-",
        '/' => .@"/",
        '*' => .@"*",
        '!' => if (self.match('=')) .@"!=" else .@"!",
        '=' => if (self.match('=')) .@"==" else .@"=",
        '<' => if (self.match('=')) .@"<=" else .@"<",
        '>' => if (self.match('=')) .@">=" else .@">",
        else => return self.makeError("Unexpected character"),
    };

    if (t_type == .ERROR) {
        return self.makeError("Unexpected character");
    }

    return self.makeToken(t_type, self.source[self.start..self.current]);
}

fn number(self: *Scanner) Token {
    const isDigit = std.ascii.isDigit;

    while (!self.isAtEnd() and isDigit(self.peek().?)) {
        self.advance();
    }

    if (self.peek() == '.' and isDigit(self.peekNext() orelse '-')) {
        self.advance();
        while (!self.isAtEnd() and isDigit(self.peek().?)) {
            self.advance();
        }
    }

    return .{
        .type = .NUMBER,
        .line = self.line,
        .lexeme = self.source[self.start..self.current],
    };
}

fn string(self: *Scanner) Token {
    while (!self.isAtEnd() and self.peek() != '"') {
        if (self.peek() == '\n') {
            self.line += 1;
        }
        self.advance();
    }
    if (self.isAtEnd()) {
        return self.makeError("Unterminated string");
    }

    self.advance(); // capture closing "

    return .{
        .type = .STRING,
        .line = self.line,
        .lexeme = self.source[self.start..self.current],
    };
}

fn identifier(self: *Scanner) Token {
    const allowed_chars = struct {
        const a = std.ascii;
        fn is_identifier_char(c: u8) bool {
            return a.isAlphanumeric(c) or c == '_';
        }
    };
    while (!self.isAtEnd() and allowed_chars.is_identifier_char(self.peek().?)) {
        self.advance();
    }

    const lexeme = self.source[self.start..self.current];
    if (Keywords.get(lexeme)) |t_type| {
        return .{
            .type = t_type,
            .line = self.line,
            .lexeme = lexeme,
        };
    }

    return .{
        .type = .IDENTIFIER,
        .line = self.line,
        .lexeme = lexeme,
    };
}

fn skipWhitespaceAndComment(self: *Scanner) void {
    while (self.peek()) |c| {
        switch (c) {
            '\n' => {
                self.line += 1;
                self.advance();
            },
            ' ', '\t', '\r' => self.advance(),
            '/' => {
                if (self.peekNext() != '/') {
                    return;
                }
                while (self.peek() != '\n' and !self.isAtEnd()) {
                    self.advance();
                }
            },
            else => return,
        }
    }
}

fn match(self: *Scanner, check: u8) bool {
    if (self.peek() != check) return false;
    self.advance();
    return true;
}

fn peekNext(self: *Scanner) ?u8 {
    if (self.current >= self.source.len - 1) return null;
    return self.source[self.current + 1];
}

fn peek(self: *Scanner) ?u8 {
    if (self.isAtEnd()) return null;
    return self.source[self.current];
}

fn isAtEnd(self: *Scanner) bool {
    return self.current >= self.source.len;
}

fn advance(self: *Scanner) void {
    self.current += 1;
}

fn makeToken(self: *Scanner, t_type: Token.Type, lexeme: []const u8) Token {
    return .{
        .type = t_type,
        .line = self.line,
        .lexeme = lexeme,
    };
}

fn makeError(self: *Scanner, msg: []const u8) Token {
    return .{
        .type = .ERROR,
        .line = self.line,
        .lexeme = msg,
    };
}
