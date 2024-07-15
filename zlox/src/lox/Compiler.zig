const std = @import("std");
const StdOut = std.io.getStdOut();

const Scanner = @import("Scanner.zig");

pub fn compile(source: []const u8) !void {
    var scanner = Scanner.init(source);

    var line: usize = undefined;
    while (true) {
        const token = scanner.scanToken();
        if (token.line != line) {
            try StdOut.writer().print("{d: <4} ", .{token.line});
            line = token.line;
        } else {
            try StdOut.writeAll("   | ");
        }

        try StdOut.writer().print("{} '{s}'", .{ token.token_type, token.start[0..token.length] });

        if (token.token_type == .EOF) {
            break;
        }
    }
}
