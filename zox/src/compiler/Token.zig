const std = @import("std");

lexeme: []const u8,
line: usize,

type: Type,

pub fn format(token: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("TOKEN {s} - '{s}'", .{ @tagName(token.type), token.lexeme });
}

pub const Type = enum {
    @"(",
    @")",
    @"{",
    @"}",
    @",",
    @";",
    @"+",
    @"-",
    @"/",
    @"*",

    @"!",
    @"!=",
    @"=",
    @"==",
    @"<",
    @"<=",
    @">",
    @">=",

    IDENTIFIER,
    STRING,
    NUMBER,

    AND,
    ELSE,
    FALSE,
    FOR,
    FUN,
    IF,
    NIL,
    OR,
    PRINT,
    RETURN,
    TRUE,
    VAR,
    WHILE,

    EOF,
    ERROR,
};
