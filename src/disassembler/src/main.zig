//=============================================================//
//                                                             //
//                           MAIN                              //
//                                                             //
//   Licensed under GNU General Public License version 3.      //
//                                                             //
//=============================================================//

const std = @import("std");
const builtin = @import("builtin");
const machine = @import("shared").machine;
const specs = @import("shared").specifications;
const warn = @import("shared").warn;
const disassembler = @import("disassemble.zig");
const clap = @import("clap.zig");
const streams = @import("shared").streams;

pub fn main() !void {
    // set up allocator
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    const gpa, const is_debug_alloc = switch (builtin.mode) {
        .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
        .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
    };
    defer if (is_debug_alloc) {
        _ = debug_allocator.deinit();
    };

    // command-line flags, filenames and filepath specifications
    const flags = try clap.Flags.Parse(gpa);
    defer flags.Deinit();
    if (flags.help == true) {
        streams.bufStdoutPrint(clap.Flags.Help_String(), .{}) catch unreachable;
        return;
    }
    if (flags.version == true) {
        streams.bufStdoutPrint(clap.Flags.Version_String(), .{}) catch unreachable;
        return;
    }
    if (std.mem.eql(u8, flags.input_rom_filename.?, "stdin")) {
        warn.Warn_Message("input through stdin input not implemented yet.", .{});
    }

    var rom: [specs.bytelen.rom]u8 = undefined;
    const rom_filestream = std.fs.cwd().openFile(flags.input_rom_filename.?, .{}) catch |err| {
        warn.Fatal_Error_Message("could not open file \"{?s}\"!", .{flags.input_rom_filename});
        if (builtin.mode == .Debug) return err else return;
    };
    const rom_filesize: usize = rom_filestream.readAll(&rom) catch |err| {
        warn.Fatal_Error_Message("could not read file contents!", .{});
        if (builtin.mode == .Debug) return err else return;
    };
    const rom_header: specs.Header = specs.Header.Parse_From_Byte_Array(rom[0..16].*);

    if (flags.log_header) {
        streams.bufStdoutPrint("HEADER INFO:\n", .{}) catch unreachable;
        streams.bufStdoutPrint("magic number: {}\n", .{rom_header.magic_number}) catch unreachable;
        streams.bufStdoutPrint("assembly version: {}\n", .{rom_header.language_version}) catch unreachable;
        streams.bufStdoutPrint("entry point address: 0x{X:0>4}\n", .{rom_header.entry_point}) catch unreachable;
        streams.bufStdoutPrint("rom debug enable: {}\n\n", .{rom_header.debug_mode}) catch unreachable;
    }

    disassembler.Disassemble_Rom(gpa, flags, rom, rom_filesize, rom_header) catch |err| {
        warn.Fatal_Error_Message("disassembly failed!", .{});
        if (builtin.mode == .Debug) return err else return;
    };
}
