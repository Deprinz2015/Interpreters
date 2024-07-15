const std = @import("std");

const Scanner = @This();

start: usize,
current: usize,
source: []const u8,
line: usize,

pub fn init(source: []const u8) Scanner {
    return .{
        .start = 0,
        .current = 0,
        .source = source,
        .line = 1,
    };
}

pub fn scanToken(self: *Scanner) Token {
    self.start = self.current;

    if (self.isAtEnd()) {
        return self.makeToken(.EOF);
    }

    const c = self.advanceWithValue();
    if (isDigit(c)) {
        return self.number();
    }

    if (isAlpha(c)) {
        return self.identifier();
    }

    switch (c) {
        '(' => return self.makeToken(.LEFT_PAREN),
        ')' => return self.makeToken(.RIGHT_PAREN),
        '{' => return self.makeToken(.LEFT_BRACE),
        '}' => return self.makeToken(.RIGHT_BRACE),
        ';' => return self.makeToken(.SEMICOLON),
        ',' => return self.makeToken(.COMMA),
        '.' => return self.makeToken(.DOT),
        '-' => return self.makeToken(.MINUS),
        '+' => return self.makeToken(.PLUS),
        '/' => return self.makeToken(.SLASH),
        '*' => return self.makeToken(.STAR),
        '!' => {
            if (self.match('=')) {
                return self.makeToken(.BANG_EQUAL);
            }
            return self.makeToken(.BANG);
        },
        '=' => {
            if (self.match('=')) {
                return self.makeToken(.EQUAL_EQUAL);
            }
            return self.makeToken(.EQUAL);
        },
        '<' => {
            if (self.match('=')) {
                return self.makeToken(.LESS_EQUAL);
            }
            return self.makeToken(.LESS);
        },
        '>' => {
            if (self.match('=')) {
                return self.makeToken(.GREATER_EQUAL);
            }
            return self.makeToken(.GREATER);
        },
        '"' => return self.string(),
        else => {
            return self.errorToken("Unexpected character.");
        },
    }
}

fn isAtEnd(self: *Scanner) bool {
    return self.current >= self.source.len;
}

fn advance(self: *Scanner) void {
    self.current += 1;
}

fn advanceWithValue(self: *Scanner) u8 {
    self.advance();
    return self.source[self.current - 1];
}

fn peek(self: *Scanner) u8 {
    return self.source[self.current];
}

fn peekNext(self: *Scanner) ?u8 {
    if (self.isAtEnd()) {
        return null;
    }
    return self.source[self.current + 1];
}

fn match(self: *Scanner, expected: u8) bool {
    if (self.isAtEnd()) {
        return false;
    }
    if (self.source[self.current] != expected) {
        return false;
    }
    self.current += 1;
    return true;
}

fn makeToken(self: *Scanner, token_type: TokenType) Token {
    return .{
        .token_type = token_type,
        .start = self.source.ptr[self.start..],
        .length = self.current - self.start,
        .line = self.line,
    };
}

fn errorToken(self: *Scanner, msg: []const u8) Token {
    return .{
        .token_type = .ERROR,
        .start = msg.ptr,
        .length = msg.len,
        .line = self.line,
    };
}

fn skipWhitespace(self: *Scanner) void {
    while (true) {
        const c = self.peek();
        switch (c) {
            ' ', '\t', '\r' => self.advance(),
            '\n' => {
                self.line += 1;
                self.advance();
            },
            '/' => {
                if (self.peekNext() == '/') {
                    while (self.peek() != '\n' and !self.isAtEnd()) {
                        self.advance();
                    }
                } else {
                    return;
                }
            },
            else => return,
        }
    }
}

fn string(self: *Scanner) Token {
    while (self.peek() != '"' and !self.isAtEnd()) {
        if (self.peek() == '\n') {
            self.line += 1;
        }
        self.advance();
    }

    if (self.isAtEnd()) {
        return self.errorToken("Unterminated string.");
    }

    self.advance();
    return self.makeToken(.STRING);
}

fn number(self: *Scanner) Token {
    while (isDigit(self.peek())) {
        self.advance();
    }

    if (self.peek() == '.' and self.peekNext() != null and isDigit(self.peekNext().?)) {
        self.advance();

        while (isDigit(self.peek())) {
            self.advance();
        }
    }

    return self.makeToken(.NUMBER);
}

fn identifier(self: *Scanner) Token {
    while (isAlpha(self.peek()) or isDigit(self.peek())) {
        self.advance();
    }

    return self.makeToken(self.identifierType());
}

fn identifierType(self: *Scanner) TokenType {
    _ = self;
    return .IDENTIFIER;
}

fn isDigit(c: u8) bool {
    return std.ascii.isDigit(c);
}

fn isAlpha(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

const Token = struct {
    token_type: TokenType,
    start: [*]const u8,
    length: usize,
    line: usize,
};

const TokenType = enum {
    // Single-character tokens.
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACE,
    RIGHT_BRACE,
    COMMA,
    DOT,
    MINUS,
    PLUS,
    SEMICOLON,
    SLASH,
    STAR,
    // One or two character tokens.
    BANG,
    BANG_EQUAL,
    EQUAL,
    EQUAL_EQUAL,
    GREATER,
    GREATER_EQUAL,
    LESS,
    LESS_EQUAL,
    // Literals.
    IDENTIFIER,
    STRING,
    NUMBER,
    // Keywords.
    AND,
    CLASS,
    ELSE,
    FALSE,
    FOR,
    FUN,
    IF,
    NIL,
    OR,
    PRINT,
    RETURN,
    SUPER,
    THIS,
    TRUE,
    VAR,
    WHILE,

    ERROR,
    EOF,
};
