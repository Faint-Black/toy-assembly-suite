const std = @import("std");

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    stdout.print("Under construction!\n", .{}) catch unreachable;
}
