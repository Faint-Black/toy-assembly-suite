//=============================================================//
//                                                             //
//                           UTILS                             //
//                                                             //
//   General-use global functions, constants and variables.    //
//                                                             //
//=============================================================//

const std = @import("std");

/// suitable for replacing harcoded values on array lengths
pub const buffsize = enum {
    pub const small: usize = 256;
    pub const medium: usize = 1024;
    pub const large: usize = 4096;
};

/// only meant for debugging as terminal colors aren't portable!
pub const textColor = enum {
    pub const red: []const u8 = "\x1b[31m";
    pub const red_bold: []const u8 = "\x1b[31;1m";
    pub const red_dim: []const u8 = "\x1b[31;2m";
    pub const green: []const u8 = "\x1b[32m";
    pub const green_bold: []const u8 = "\x1b[32;1m";
    pub const green_dim: []const u8 = "\x1b[32;2m";
    pub const yellow: []const u8 = "\x1b[33m";
    pub const yellow_bold: []const u8 = "\x1b[33;1m";
    pub const yellow_dim: []const u8 = "\x1b[33;2m";
    pub const bold: []const u8 = "\x1b[1m";
    pub const reset: []const u8 = "\x1b[0m";
};

/// writes file contents to the input buffer, then returns the amount of bytes written
pub fn Read_File_Into_Buffer(buff: []u8, file: std.fs.File) !usize {
    return try file.reader().read(buff[0..]);
}

/// allocates the contents of a file into a u8 slice
pub fn Read_And_Allocate_File(file: std.fs.File, allocator: std.mem.Allocator, maxsize: usize) ![]u8 {
    return try file.readToEndAlloc(allocator, maxsize);
}

/// writes a slice of bytes into a file
pub fn Write_To_File(file: std.fs.File, bytes: []const u8) !void {
    try file.writeAll(bytes);
}

/// spacebar, null terminator, newline or tabs
pub fn Is_Char_Whitespace(c: u8) bool {
    return std.ascii.isWhitespace(c) or (c == 0);
}

/// [a-z] or [A-Z]
pub fn Is_Char_Letter(c: u8) bool {
    return std.ascii.isAlphabetic(c);
}

/// [0-9]
pub fn Is_Char_Decimal_Digit(c: u8) bool {
    return std.ascii.isDigit(c);
}

/// [0-9] or [a-f] or [A-F]
pub fn Is_Char_Hexadecimal_Digit(c: u8) bool {
    return std.ascii.isHex(c);
}

/// places an element at the end of a buffer, dictated by buffer_size
pub fn Append_Element_To_Buffer(comptime T: type, buffer: []T, buffer_size: *usize, element: T) !void {
    if (buffer_size.* >= buffer.len)
        return error.BufferOverflow;
    buffer[buffer_size.*] = element;
    buffer_size.* += 1;
}

/// returns an allocated copy of the input slice
pub fn Copy_Of_Slice(comptime T: type, allocator: std.mem.Allocator, slice: []const T) ![]T {
    return try allocator.dupe(T, slice);
}

/// removes an element from the array and shift all right elements to the left
pub fn Remove_And_Shift(comptime T: type, buffer: []T, buffer_size: *usize, remove_index: usize) !void {
    if (remove_index >= buffer_size.*) return error.BadIndex;
    for (remove_index..buffer.len) |index| {
        if ((index + 1) == buffer.len) break;
        buffer[index] = buffer[index + 1];
    }
    buffer_size.* -= 1;
}

/// alias for better readability
pub fn Append_Char_To_String(buffer: []u8, buffer_size: *usize, character: u8) !void {
    try Append_Element_To_Buffer(u8, buffer, buffer_size, character);
}

/// alias for better readability
pub fn Copy_Of_ConstString(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    return Copy_Of_Slice(u8, allocator, str);
}

/// there's no builtin for this???
pub fn Int_To_Bool(num: anytype) bool {
    return num != 0;
}

/// meant for use inside Thread.sleep function parameters
pub fn Milliseconds_To_Nanoseconds(milliseconds: u64) u64 {
    return milliseconds * 1_000_000;
}

//-------------------------------------------------------------//
// ONLY TESTS BELOW THIS POINT                                 //
//-------------------------------------------------------------//
test "check cosmic integrity of modern mathematics" {
    try std.testing.expectEqual(1 + 1, 2);
}

test "is character whitespace" {
    try std.testing.expect(Is_Char_Whitespace(' ') == true);
    try std.testing.expect(Is_Char_Whitespace('\t') == true);
    try std.testing.expect(Is_Char_Whitespace('\n') == true);
}

test "is character an alphabetic letter" {
    try std.testing.expect(Is_Char_Letter('1') == false);
    try std.testing.expect(Is_Char_Letter('\n') == false);
    try std.testing.expect(Is_Char_Letter('Z') == true);
    try std.testing.expect(Is_Char_Letter('a') == true);
}

test "is character a decimal numeric digit" {
    try std.testing.expect(Is_Char_Decimal_Digit('0') == true);
    try std.testing.expect(Is_Char_Decimal_Digit('9') == true);
    try std.testing.expect(Is_Char_Decimal_Digit('5') == true);
    try std.testing.expect(Is_Char_Decimal_Digit('a') == false);
    try std.testing.expect(Is_Char_Decimal_Digit('A') == false);
    try std.testing.expect(Is_Char_Decimal_Digit('f') == false);
    try std.testing.expect(Is_Char_Decimal_Digit('F') == false);
}

test "is character a hexadecimal numeric digit" {
    try std.testing.expect(Is_Char_Hexadecimal_Digit('0') == true);
    try std.testing.expect(Is_Char_Hexadecimal_Digit('9') == true);
    try std.testing.expect(Is_Char_Hexadecimal_Digit('5') == true);
    try std.testing.expect(Is_Char_Hexadecimal_Digit('a') == true);
    try std.testing.expect(Is_Char_Hexadecimal_Digit('A') == true);
    try std.testing.expect(Is_Char_Hexadecimal_Digit('f') == true);
    try std.testing.expect(Is_Char_Hexadecimal_Digit('F') == true);
}

test "element buffer appending" {
    var buffer: [64]u8 = undefined;
    var bufsize: usize = 0;

    try Append_Char_To_String(&buffer, &bufsize, 'f');
    try Append_Char_To_String(&buffer, &bufsize, 'o');
    try Append_Char_To_String(&buffer, &bufsize, 'o');
    try Append_Char_To_String(&buffer, &bufsize, 'b');
    try Append_Char_To_String(&buffer, &bufsize, 'a');
    try Append_Char_To_String(&buffer, &bufsize, 'r');

    try std.testing.expectEqualStrings("foobar", buffer[0..bufsize]);
    try std.testing.expectEqual(6, bufsize);
}

test "copy of slice" {
    const string = try Copy_Of_ConstString(std.testing.allocator, "Huzzah!");
    const huzzah = "Huzzah!";
    try std.testing.expectEqualStrings(huzzah, string);
    try std.testing.expectEqual(huzzah.len, string.len);
    try std.testing.expect(huzzah.ptr != string.ptr);
    std.testing.allocator.free(string);
}

test "removing from buffer" {
    var buffer: [64]i32 = undefined;
    var compare: [64]i32 = undefined;
    var bufsize: usize = 7;
    const cmpsize: usize = 5;

    buffer[0] = 0;
    buffer[1] = 1;
    buffer[2] = 2;
    buffer[3] = 1337;
    buffer[4] = 6502;
    buffer[5] = 3;
    buffer[6] = 4;

    compare[0] = 0;
    compare[1] = 1;
    compare[2] = 2;
    compare[3] = 3;
    compare[4] = 4;

    try Remove_And_Shift(i32, &buffer, &bufsize, 3);
    try Remove_And_Shift(i32, &buffer, &bufsize, 3);

    try std.testing.expectEqual(5, bufsize);
    try std.testing.expectEqual(cmpsize, bufsize);
    try std.testing.expectEqualSlices(i32, compare[0..cmpsize], buffer[0..bufsize]);
}

test "milliseconds to nanoseconds" {
    try std.testing.expectEqual(1_000_000, Milliseconds_To_Nanoseconds(1));
    try std.testing.expectEqual(10_000_000, Milliseconds_To_Nanoseconds(10));
    try std.testing.expectEqual(100_000_000, Milliseconds_To_Nanoseconds(100));
    try std.testing.expectEqual(1_000_000_000, Milliseconds_To_Nanoseconds(1000));
}
