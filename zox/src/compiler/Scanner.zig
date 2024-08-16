const std = @import("std");
const Token = @import("Token.zig");

const Scanner = @This();

source: []const u8,
current: usize,
start: usize,
line: usize,

pub fn init(source: []const u8) Scanner {
    return .{
        .source = source,
    };
}

pub fn getNextToken(self: *Scanner) Token {
    if (self.isAtEnd()) {
        return .{
            .type = .EOF,
            .line = self.line,
            .lexeme = "",
        };
    }
}

fn isAtEnd(self: *Scanner) bool {
    return self.current >= self.source.len;
}

fn advance(self: *Scanner) void {
    self.current += 1;
}
