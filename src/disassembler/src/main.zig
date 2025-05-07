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

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    // use DebugAllocator on debug mode
    // use ArenaAllocator with page_allocator on release mode
    var debug_struct_allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_struct_allocator.deinit();
    var arena_struct_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena_struct_allocator.deinit();
    const global_allocator: std.mem.Allocator = if (builtin.mode == .Debug) debug_struct_allocator.allocator() else arena_struct_allocator.allocator();

    // command-line flags, filenames and filepath specifications
    const flags = try clap.Flags.Parse(global_allocator);
    defer flags.Deinit();
    if (flags.help == true) {
        stdout.print(clap.Flags.Help_String(), .{}) catch unreachable;
        return;
    }
    if (flags.version == true) {
        stdout.print(clap.Flags.Version_String(), .{}) catch unreachable;
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
        stdout.print("HEADER INFO:\n", .{}) catch unreachable;
        stdout.print("magic number: {}\n", .{rom_header.magic_number}) catch unreachable;
        stdout.print("assembly version: {}\n", .{rom_header.language_version}) catch unreachable;
        stdout.print("entry point address: 0x{X:0>4}\n", .{rom_header.entry_point}) catch unreachable;
        stdout.print("rom debug enable: {}\n\n", .{rom_header.debug_mode}) catch unreachable;
    }

    disassembler.Disassemble_Rom(global_allocator, flags, rom, rom_filesize, rom_header) catch |err| {
        warn.Fatal_Error_Message("disassembly failed!", .{});
        if (builtin.mode == .Debug) return err else return;
    };
}
