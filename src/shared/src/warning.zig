//=============================================================//
//                                                             //
//                     ERRORS AND WARNINGS                     //
//                                                             //
//   Defines warning/error logging functions, these do not     //
//  alter the execution flow of the program, only display      //
//  terminal messages for the user.                            //
//                                                             //
//=============================================================//

const std = @import("std");
const color = @import("utils.zig").textColor;

pub fn Warn_Message(comptime msg: []const u8, fmt: anytype) void {
    var buf: [4096]u8 = undefined;
    const formatted_msg = std.fmt.bufPrint(&buf, msg, fmt) catch unreachable;
    std.debug.print(color.yellow_bold ++ "WARNING:" ++ color.reset ++ " {s}\n", .{formatted_msg});
}

pub fn Error_Message(comptime msg: []const u8, fmt: anytype) void {
    var buf: [4096]u8 = undefined;
    const formatted_msg = std.fmt.bufPrint(&buf, msg, fmt) catch unreachable;
    std.debug.print(color.red_bold ++ "ERROR:" ++ color.reset ++ " {s}\n", .{formatted_msg});
}

pub fn Fatal_Error_Message(comptime msg: []const u8, fmt: anytype) void {
    var buf: [4096]u8 = undefined;
    const formatted_msg = std.fmt.bufPrint(&buf, msg, fmt) catch unreachable;
    std.debug.print(color.red_bold ++ "FATAL ERROR:" ++ color.reset ++ " {s}\n", .{formatted_msg});
}
