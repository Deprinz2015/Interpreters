const std = @import("std");

pub const Value = union(enum) {
    number: Number,

    const Number = struct {
        value: f64,
    };
};
