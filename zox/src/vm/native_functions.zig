const std = @import("std");
const VM = @import("Machine.zig");
const Value = @import("value.zig").Value;

pub fn time(args: []Value, vm: *VM) Value {
    if (args.len != 0) {
        vm.runtimeError("Native function 'time' does not accept any arguments", .{}) catch {};
        return .nil;
    }

    const millis: f64 = @floatFromInt(std.time.milliTimestamp());
    return .{ .number = millis };
}
