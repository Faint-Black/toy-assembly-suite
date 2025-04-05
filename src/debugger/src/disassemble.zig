//=============================================================//
//                                                             //
//                        DISASSEMBLER                         //
//                                                             //
//   Responsible for the disassembler debugger function, which //
//  turns a ROM binary back into human readable instructions.  //
//                                                             //
//=============================================================//

const std = @import("std");
const clap = @import("clap.zig");
const specs = @import("shared").specifications;
const utils = @import("shared").utils;
const machine = @import("shared").machine;

pub fn Disassemble_Rom(allocator: std.mem.Allocator, rom: []const u8, original_rom_size: usize, header: specs.Header) !void {
    // TODO: rename
    var buffer1: [utils.buffsize.large]u8 = undefined;
    var buffer2: [utils.buffsize.large]u8 = undefined;
    var buffer3: [utils.buffsize.large]u8 = undefined;

    // completely disconsidered if ROM is not in debug mode
    // key = label address
    // val = label string name
    var label_hashmap: ?std.AutoArrayHashMap(u16, []const u8) = null;
    if (header.debug_mode) {
        label_hashmap = Resolve_Metadata_Labels(allocator, rom, original_rom_size, header);
    }
    defer {
        if (label_hashmap) |hashmap| {
            for (hashmap.values()) |allocated_label_str| {
                hashmap.allocator.free(allocated_label_str);
            }
            label_hashmap.?.deinit();
        }
    }

    std.debug.print("BEGIN DISASSEMBLY DUMP:\n", .{});
    var PC: u16 = 0;
    while (true) {
        if (PC == 0) {
            const addr_str = Address_String(&buffer1, 0);
            const instr_bytes_str = Instruction_Bytes_String(&buffer2, rom[0..specs.Header.header_byte_size]);
            std.debug.print("{s}: {s} header bytes\n", .{ addr_str, instr_bytes_str });
            PC = specs.Header.header_byte_size;
            continue;
        }
        if (PC < header.entry_point) {
            const addr_str = Address_String(&buffer1, PC);
            const instr_bytes_str = Instruction_Bytes_String(&buffer2, rom[PC..header.entry_point]);
            std.debug.print("{s}: {s} data bytes\n", .{ addr_str, instr_bytes_str });
            PC = header.entry_point;
            continue;
        }
        if (PC >= original_rom_size) {
            const start = Address_String(&buffer1, PC);
            const end = Address_String(&buffer2, specs.rom_address_space - 1);
            std.debug.print("{s} to {s} = trash bytes\n", .{ start, end });
            break;
        }

        const opcode_enum: specs.Opcode = @enumFromInt(rom[PC]);
        if (header.debug_mode and opcode_enum == .DEBUG_METADATA_SIGNAL) {
            const metadata_type: specs.DebugMetadataType = @enumFromInt(rom[PC + 1]);
            const metadata_bytelen: u16 = @truncate(metadata_type.Metadata_Length(rom[PC..]) catch 0);
            const addr_str = Address_String(&buffer1, PC);
            const instr_bytes_str = Instruction_Bytes_String(&buffer2, rom[PC .. PC + metadata_bytelen]);
            std.debug.print("{s}: {s} debug metadata (LABEL NAME \"{?s}\")\n", .{ addr_str, instr_bytes_str, label_hashmap.?.get(PC + metadata_bytelen) });
            PC += metadata_bytelen;
            continue;
        }

        const addr_str = Address_String(&buffer1, PC);
        const instr_bytes_str = Instruction_Bytes_String(&buffer2, rom[PC .. PC + opcode_enum.Instruction_Byte_Length()]);
        const instr_str = try opcode_enum.Instruction_String(&buffer3, rom[PC .. PC + opcode_enum.Instruction_Byte_Length()]);
        std.debug.print("{s}: {s} {s}\n", .{ addr_str, instr_bytes_str, instr_str });

        PC += opcode_enum.Instruction_Byte_Length();
    }
}

//-------------------------------------------------------------//
// STATIC PRIVATE FUNCTIONS                                    //
//-------------------------------------------------------------//

fn Address_String(buffer: []u8, addr: u16) []const u8 {
    return std.fmt.bufPrint(buffer, "${x:0>4}", .{addr}) catch {
        @panic("format print failed!");
    };
}

fn Instruction_Bytes_String(buffer: []u8, bytes: []const u8) []const u8 {
    const indent = "       ";
    const entries_per_line = 8;
    const chars_per_entry = 3;
    // TODO: over-engineered non-zero integer divCeil
    const loop_count: usize = if (bytes.len % entries_per_line == 0 and bytes.len != 0) entries_per_line * ((bytes.len / entries_per_line) + 0) else entries_per_line * ((bytes.len / entries_per_line) + 1);

    var str_index: usize = 0;
    for (0..loop_count) |i| {
        if ((i != 0) and (i % entries_per_line == 0)) {
            _ = std.fmt.bufPrint(buffer[str_index..], "\n{s}", .{indent}) catch
                @panic("format print failed!");
            str_index += 1;
            str_index += indent.len;
        }
        if (i >= bytes.len) {
            _ = std.fmt.bufPrint(buffer[str_index..], ".. ", .{}) catch
                @panic("format print failed!");
        } else {
            _ = std.fmt.bufPrint(buffer[str_index..], "{x:0>2} ", .{bytes[i]}) catch
                @panic("format print failed!");
        }
        str_index += chars_per_entry;
    }
    _ = std.fmt.bufPrint(buffer[str_index..], "= ", .{}) catch
        @panic("format print failed!");
    str_index += 2;

    return buffer[0..str_index];
}

/// returns null on fail
fn Resolve_Metadata_Labels(allocator: std.mem.Allocator, rom: []const u8, original_rom_size: usize, header: specs.Header) ?std.AutoArrayHashMap(u16, []const u8) {
    var result = std.AutoArrayHashMap(u16, []const u8).init(allocator);

    var buffer: [512]u8 = undefined;
    var buf_len: usize = 0;

    var PC: u16 = header.entry_point;
    var inside_metadata: bool = false;
    var metadata_type: ?specs.DebugMetadataType = null;
    var opcode: specs.Opcode = undefined;
    while (true) {
        if (PC >= original_rom_size)
            break;

        // first byte is the debug metadata content type
        if (metadata_type == null and inside_metadata == true) {
            metadata_type = @enumFromInt(rom[PC]);
            PC += 1;
            continue;
        }
        if (rom[PC] == @intFromEnum(specs.Opcode.DEBUG_METADATA_SIGNAL)) {
            metadata_type = null;
            // metadata contents begin
            if (inside_metadata == false) {
                inside_metadata = true;
                PC += 1;
                continue;
            }
            // metadata contents end
            if (inside_metadata == true) {
                inside_metadata = false;
                PC += 1;
                const label_allocated_string = utils.Copy_Of_ConstString(allocator, buffer[0..buf_len]) catch
                    return null;
                result.put(PC, label_allocated_string) catch
                    return null;
                buf_len = 0;
                continue;
            }
        }
        if (inside_metadata and metadata_type.? == .LABEL_NAME) {
            buffer[buf_len] = rom[PC];
            buf_len += 1;
            PC += 1;
            continue;
        }

        // skip instruction bytes
        opcode = @enumFromInt(rom[PC]);
        PC += opcode.Instruction_Byte_Length();
    }

    return result;
}

//-------------------------------------------------------------//
// ONLY TESTS BELOW THIS POINT                                 //
//-------------------------------------------------------------//
test "address strings" {
    var buffer: [512]u8 = undefined;
    var str: []const u8 = undefined;

    str = Address_String(&buffer, 0xFFFF);
    try std.testing.expectEqualStrings("$ffff", str);
    str = Address_String(&buffer, 0);
    try std.testing.expectEqualStrings("$0000", str);
    str = Address_String(&buffer, 16);
    try std.testing.expectEqualStrings("$0010", str);
    str = Address_String(&buffer, 0xABCD);
    try std.testing.expectEqualStrings("$abcd", str);
}

test "instruction bytes strings" {
    var buffer: [512]u8 = undefined;
    var str: []const u8 = undefined;
    const nl = " \n       ";

    str = Instruction_Bytes_String(&buffer, &.{});
    try std.testing.expectEqualStrings(".. .. .. .. .. .. .. .. = ", str);
    str = Instruction_Bytes_String(&buffer, &.{ 16, 17, 18, 19 });
    try std.testing.expectEqualStrings("10 11 12 13 .. .. .. .. = ", str);
    str = Instruction_Bytes_String(&buffer, &.{ 0, 1, 2, 3, 4, 5, 6, 7 });
    try std.testing.expectEqualStrings("00 01 02 03 04 05 06 07 = ", str);
    str = Instruction_Bytes_String(&buffer, &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8 });
    try std.testing.expectEqualStrings("00 01 02 03 04 05 06 07" ++ nl ++ "08 .. .. .. .. .. .. .. = ", str);
    str = Instruction_Bytes_String(&buffer, &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 });
    try std.testing.expectEqualStrings("00 01 02 03 04 05 06 07" ++ nl ++ "08 09 0a 0b 0c 0d 0e 0f" ++ nl ++ "10 .. .. .. .. .. .. .. = ", str);
}
