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

pub fn main() !void {
    // use DebugAllocator on debug mode
    // use SmpAllocator on release mode
    var debug_struct_allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_struct_allocator.deinit();
    var global_allocator: std.mem.Allocator = if (builtin.mode == .Debug) debug_struct_allocator.allocator() else std.heap.smp_allocator;

    // begin benchmark
    var timer = std.time.Timer.start() catch |err| {
        warn.Fatal_Error_Message("could not begin benchmark timer!", .{});
        if (builtin.mode == .Debug) return err else return;
    };

    // keep track of identifiers through all steps
    var global_symbol_table = sym.SymbolTable.Init(global_allocator);
    defer global_symbol_table.Deinit();

    // command-line flags, filenames and filepath specifications
    const flags = clap.Flags.Parse(global_allocator) catch |err| {
        warn.Fatal_Error_Message("could not parse command line flags!", .{});
        if (builtin.mode == .Debug) return err else return;
    };
    defer flags.Deinit();
    if (flags.help == true) {
        std.debug.print(clap.Flags.Help_String(), .{});
        return;
    }
    if (flags.version == true) {
        std.debug.print(clap.Flags.Version_String(), .{});
        return;
    }
    if (std.mem.eql(u8, flags.input_filename.?, "stdin")) {
        warn.Warn_Message("input through stdin input not implemented yet.", .{});
    }
    if (flags.debug_mode == true) {
        std.debug.print("DEBUG MODE ENABLED\n\n", .{});
    }

    // [DEBUG OUTPUT] print flag informations
    if (flags.print_flags) {
        std.debug.print("invoked binary: {?s}\n", .{flags.binary_directory});
        std.debug.print("input filepath: {?s}\n", .{flags.input_filename});
        std.debug.print("output filepath: {?s}\n", .{flags.output_filename});
        std.debug.print("debug mode flag: {}\n", .{flags.debug_mode});
        std.debug.print("print flags: {}\n", .{flags.print_flags});
        std.debug.print("print lexed tokens: {}\n", .{flags.print_lexed_tokens});
        std.debug.print("print stripped tokens: {}\n", .{flags.print_stripped_tokens});
        std.debug.print("print expanded tokens: {}\n", .{flags.print_expanded_tokens});
        std.debug.print("print symbol table: {}\n", .{flags.print_symbol_table});
        std.debug.print("print anon labels: {}\n", .{flags.print_anon_labels});
        std.debug.print("print rom: {}\n", .{flags.print_rom_bytes});
    }

    // load file into a newly allocated buffer
    const filestream = std.fs.cwd().openFile(flags.input_filename.?, .{}) catch |err| {
        warn.Fatal_Error_Message("could not open file \"{?s}\"!", .{flags.input_filename});
        if (builtin.mode == .Debug) return err else return;
    };
    const filecontents = filestream.readToEndAlloc(global_allocator, 4096) catch |err| {
        warn.Fatal_Error_Message("could not read or allocate file contents!", .{});
        if (builtin.mode == .Debug) return err else return;
    };
    defer global_allocator.free(filecontents);

    // lex and parse input file into individual tokens
    const lexed_tokens = lex.Lexer(global_allocator, filecontents) catch |err| {
        warn.Fatal_Error_Message("lexing failed!", .{});
        if (builtin.mode == .Debug) return err else return;
    };
    defer global_allocator.free(lexed_tokens);
    defer tok.Destroy_Tokens_Contents(global_allocator, lexed_tokens);

    // [DEBUG OUTPUT] print lexed tokens
    if (flags.print_lexed_tokens) {
        std.debug.print("\nLexed tokens:\n", .{});
        tok.Print_Token_Array(lexed_tokens);
    }

    // expand macros
    const expanded_tokens = pp.Preprocessor_Expansion(global_allocator, flags, &global_symbol_table, lexed_tokens) catch |err| {
        warn.Fatal_Error_Message("macro expansion failed!", .{});
        if (builtin.mode == .Debug) return err else return;
    };
    defer global_allocator.free(expanded_tokens);
    defer tok.Destroy_Tokens_Contents(global_allocator, expanded_tokens);

    // [DEBUG OUTPUT] print macro expanded tokens
    if (flags.print_expanded_tokens) {
        std.debug.print("\nExpanded tokens:\n", .{});
        tok.Print_Token_Array(expanded_tokens);
    }

    // start the code generation
    const rom = codegen.Generate_Rom(global_allocator, flags, &global_symbol_table, expanded_tokens) catch |err| {
        warn.Fatal_Error_Message("rom bytecode generation failed!", .{});
        if (builtin.mode == .Debug) return err else return;
    };
    defer global_allocator.free(rom);

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
    if (flags.print_symbol_table)
        global_symbol_table.Print();

    // end and print benchmark
    const nanoseconds = timer.read();
    std.debug.print("Compilation done in {}\n", .{std.fmt.fmtDuration(nanoseconds)});

    // print emit information
    if (flags.output_filename) |output_filename|
        std.debug.print("Written {} bytes to {s}\n", .{ rom.len, output_filename });
}
