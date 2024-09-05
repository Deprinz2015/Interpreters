const std = @import("std");
const ast = @import("ast.zig");

const Sema = @This();

tree: []*ast.Stmt,

pub fn scoping(self: *Sema) !void {
    _ = self;
    // TODO:
}
