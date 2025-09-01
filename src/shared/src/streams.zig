//=============================================================//
//                                                             //
//                         STREAMS                             //
//                                                             //
//   The stdout, stderr and stdin streams and their new APIs   //
//  adapters.                                                  //
//                                                             //
//=============================================================//

const std = @import("std");

var stream_buffer: [4096]u8 = undefined;

/// immediately prints to stdout
pub fn bufStdoutPrint(comptime fmt: []const u8, args: anytype) !void {
    var stdout_writer = std.fs.File.stdout().writer(&stream_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(fmt, args);
    try stdout.flush();
}

/// immediately prints to stderr
pub fn bufStderrPrint(comptime fmt: []const u8, args: anytype) !void {
    var buf: [512]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&buf);
    const stderr = &stderr_writer.interface;
    try stderr.print(fmt, args);
    try stderr.flush();
}

/// immediately read input from user into a buffer then returns the read slice
pub fn bufStdinRead(buffer: []u8, comptime limit: usize) ![]u8 {
    var buf: [512]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&buf);
    const stdin = &stdin_reader.interface;
    var w = std.Io.Writer.fixed(buffer);
    _ = try stdin.streamDelimiterLimit(&w, '\n', @enumFromInt(limit));
    return w.buffered();
}
