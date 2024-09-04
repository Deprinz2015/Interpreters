const std = @import("std");
const Value = @import("../bytecode/value.zig").Value;

pub fn print(stack: []Value, stack_top: usize) void {
    std.debug.print("Stack: ", .{});
    for (stack, 0..) |value, i| {
        if (i >= stack_top) {
            break;
        }

        std.debug.print("[ {} ]", .{value});
    }
    std.debug.print("\n", .{});
}
