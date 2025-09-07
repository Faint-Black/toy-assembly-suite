//=============================================================//
//                                                             //
//                           MAIN                              //
//                                                             //
//   Licensed under GNU General Public License version 3.      //
//                                                             //
//=============================================================//

const std = @import("std");
const builtin = @import("builtin");
const utils = @import("shared").utils;
const clap = @import("clap.zig");
const tok = @import("token.zig");
const lex = @import("lexer.zig");
const sym = @import("symbol.zig");
const pp = @import("preprocessor.zig");
const codegen = @import("codegen.zig");
const warn = @import("shared").warn;
const analysis = @import("analyzer.zig");
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

    // begin benchmark
    var timer = std.time.Timer.start() catch |err| {
        warn.Fatal_Error_Message("could not begin benchmark timer!", .{});
        return err;
    };

    // keep track of identifiers through all steps
    var global_symbol_table = sym.SymbolTable.Init(gpa);
    defer global_symbol_table.Deinit();

    // command-line flags, filenames and filepath specifications
    const flags = clap.Flags.Parse(gpa) catch |err| {
        warn.Fatal_Error_Message("could not parse command line flags!", .{});
        return err;
    };
    defer flags.Deinit();
    if (flags.help == true) {
        try streams.bufStdoutPrint(clap.Flags.Help_String(), .{});
        return;
    }
    if (flags.version == true) {
        streams.bufStdoutPrint(clap.Flags.Version_String(), .{}) catch unreachable;
        return;
    }
    if (std.mem.eql(u8, flags.input_filename.?, "stdin")) {
        warn.Warn_Message("input through stdin input not implemented yet.", .{});
    }
    if (flags.debug_mode == true) {
        streams.bufStdoutPrint("DEBUG MODE ENABLED\n\n", .{}) catch unreachable;
    }

    // [DEBUG OUTPUT] print flag informations
    if (flags.log_flags) {
        streams.bufStdoutPrint("invoked binary: {?s}\n", .{flags.binary_directory}) catch unreachable;
        streams.bufStdoutPrint("input filepath: {?s}\n", .{flags.input_filename}) catch unreachable;
        streams.bufStdoutPrint("output filepath: {?s}\n", .{flags.output_filename}) catch unreachable;
        streams.bufStdoutPrint("debug mode flag: {}\n", .{flags.debug_mode}) catch unreachable;
        streams.bufStdoutPrint("print flags: {}\n", .{flags.log_flags}) catch unreachable;
        streams.bufStdoutPrint("print lexed tokens: {}\n", .{flags.log_lexed_tokens}) catch unreachable;
        streams.bufStdoutPrint("print stripped tokens: {}\n", .{flags.log_stripped_tokens}) catch unreachable;
        streams.bufStdoutPrint("print expanded tokens: {}\n", .{flags.log_expanded_tokens}) catch unreachable;
        streams.bufStdoutPrint("print symbol table: {}\n", .{flags.log_symbol_table}) catch unreachable;
        streams.bufStdoutPrint("print anon labels: {}\n", .{flags.log_anon_labels}) catch unreachable;
        streams.bufStdoutPrint("print rom: {}\n", .{flags.log_rom_bytes}) catch unreachable;
    }

    // load file into a newly allocated buffer
    const filestream = std.fs.cwd().openFile(flags.input_filename.?, .{}) catch |err| {
        warn.Fatal_Error_Message("could not open file \"{?s}\"!", .{flags.input_filename});
        if (builtin.mode == .Debug) return err else return;
    };
    // 1 MiB filesize limit
    const max_filesize: usize = (1 << 20);
    const filecontents = filestream.readToEndAlloc(gpa, max_filesize) catch |err| {
        warn.Fatal_Error_Message("could not read or allocate file contents!", .{});
        if (builtin.mode == .Debug) return err else return;
    };
    defer gpa.free(filecontents);

    // lex and parse input file into individual tokens
    const lexed_tokens = lex.Lexer(gpa, filecontents) catch |err| {
        warn.Fatal_Error_Message("lexing failed!", .{});
        if (builtin.mode == .Debug) return err else return;
    };
    defer gpa.free(lexed_tokens);
    defer tok.Destroy_Tokens_Contents(gpa, lexed_tokens);

    // [DEBUG OUTPUT] print lexed tokens
    if (flags.log_lexed_tokens) {
        streams.bufStdoutPrint("\nLexed tokens:\n", .{}) catch unreachable;
        tok.Print_Token_Array(lexed_tokens);
    }

    // expand macros
    const expanded_tokens = pp.Preprocessor_Expansion(gpa, flags, &global_symbol_table, lexed_tokens) catch |err| {
        warn.Fatal_Error_Message("macro expansion failed!", .{});
        if (builtin.mode == .Debug) return err else return;
    };
    defer gpa.free(expanded_tokens);
    defer tok.Destroy_Tokens_Contents(gpa, expanded_tokens);

    // [DEBUG OUTPUT] print macro expanded tokens
    if (flags.log_expanded_tokens) {
        streams.bufStdoutPrint("\nExpanded tokens:\n", .{}) catch unreachable;
        tok.Print_Token_Array(expanded_tokens);
    }

    // start the code generation
    const rom = codegen.Generate_Rom(gpa, flags, &global_symbol_table, expanded_tokens) catch |err| {
        warn.Fatal_Error_Message("rom bytecode generation failed!", .{});
        if (builtin.mode == .Debug) return err else return;
    };
    defer gpa.free(rom);

    // analyze user's generated rom
    analysis.Analyze_Rom(rom) catch |err| {
        warn.Fatal_Error_Message("compilation analysis caught a fatal mistake!", .{});
        if (builtin.mode == .Debug) return err else return;
    };

    // create rom bytecode bin file relative to the current working directory
    // only perform this if an output name was specified with the "-o" flag
    if (flags.output_filename) |output_filename| {
        const rom_file = std.fs.cwd().createFile(output_filename, std.fs.File.CreateFlags{}) catch |err| {
            warn.Fatal_Error_Message("failed to create rom file!", .{});
            if (builtin.mode == .Debug) return err else return;
        };
        defer rom_file.close();
        rom_file.writeAll(rom) catch |err| {
            warn.Fatal_Error_Message("failed to write to created rom file!", .{});
            if (builtin.mode == .Debug) return err else return;
        };
    }

    // [DEBUG OUTPUT] print symbol hashtable
    if (flags.log_symbol_table)
        global_symbol_table.Print();

    // end and print benchmark
    {
        const nanoseconds = timer.read();
        var fmt_buf: [256]u8 = undefined;
        var w = std.Io.Writer.fixed(&fmt_buf);
        w.printDurationUnsigned(nanoseconds) catch unreachable;
        streams.bufStdoutPrint("Compilation done in {s}\n", .{w.buffered()}) catch unreachable;
    }

    // print emit information
    if (flags.output_filename) |output_filename|
        streams.bufStdoutPrint("Written {} bytes to {s}\n", .{ rom.len, output_filename }) catch unreachable;
}
