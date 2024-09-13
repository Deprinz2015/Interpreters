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

pub fn int(args: []Value, vm: *VM) Value {
    if (args.len != 1) {
        vm.runtimeError("Native function 'int' expects exactly one argument", .{}) catch {};
        return .nil;
    }

    const input = args[0];
    if (input != .number) {
        vm.runtimeError("Native function 'int' expects argument to be of type number", .{}) catch {};
        return .nil;
    }

    return .{ .number = @trunc(input.number) };
}
