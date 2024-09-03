const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("../compiler/ast.zig");

pub const Instruction = enum(u8) {};

pub fn translate(program: []*ast.Stmt, alloc: Allocator) []u8 {
    _ = program;
    _ = alloc;

    return &.{};
}
