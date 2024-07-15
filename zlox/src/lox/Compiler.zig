const std = @import("std");
const StdOut = std.io.getStdOut();

const Scanner = @import("Scanner.zig");
const Chunk = @import("Chunk.zig");
const Token = @import("Scanner.zig").Token;

const Parser = struct {
    current: Token,
    previous: Token,
    scanner: Scanner,

    fn advance(self: *Parser) void {
        self.previous = self.current;
        while (true) {
            self.current = self.scanner.scanToken();

            if (self.current.token_type != .ERROR) {
                break;
            }

            self.errorAtCurrent(self.current.start);
        }
    }
};

pub fn compile(source: []const u8) !Chunk {
    var scanner = Scanner.init(source);
    var parser: Parser = .{ .current = undefined, .previous = undefined, .scanner = scanner };
}
