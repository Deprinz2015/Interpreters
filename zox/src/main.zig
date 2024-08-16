const std = @import("std");
const Zli = @import("Zli");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var zli = Zli.init(alloc);
    defer zli.deinit();

    try zli.addOption("help", 'h', "Show this Help message");

    if (try zli.option(bool, "help")) {
        _ = try zli.help(std.io.getStdOut().writer(), 0);
        return;
    }
}

fn compile() void {}

fn run() void {}
