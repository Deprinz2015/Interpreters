const std = @import("std");

pub const Value = union(enum) {
    number: f64,

    pub fn equals(this: Value, that: Value) bool {
        if (std.meta.activeTag(this) != std.meta.activeTag(that)) {
            return false;
        }

        return switch (this) {
            .number => this.number == that.number,
        };
    }
};
