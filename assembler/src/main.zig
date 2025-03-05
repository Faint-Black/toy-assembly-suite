//=============================================================//
//                                                             //
//                           MAIN                              //
//                                                             //
//   Compiled with Zig 0.14.0-dev (EXPERIMENTAL DEV BUILD),    //
//  Patch notes and license details at the bottom.             //
//                                                             //
//=============================================================//

const std = @import("std");
const utils = @import("utils.zig");
const clap = @import("clap.zig");
const tok = @import("token.zig");
const lex = @import("lexer.zig");
const sym = @import("symbol.zig");
const pp = @import("preprocessor.zig");
const codegen = @import("codegen.zig");

pub fn main() !void {
    // begin benchmark
    var timer = try std.time.Timer.start();

    // debug allocator will be used for all functions
    var backing_alloc = std.heap.DebugAllocator(.{}).init;
    defer _ = backing_alloc.deinit();
    const global_allocator = backing_alloc.allocator();

    // keep track of identifiers through all steps
    var global_symbol_table = sym.SymbolTable.Init(global_allocator);
    defer global_symbol_table.Deinit();

    // command-line flags, filenames and filepath specifications
    const flags = try clap.Parse_Arguments(global_allocator);
    defer flags.Deinit();
    if (flags.help == true) {
        try std.io.getStdOut().writer().print("{s}", .{clap.Help_String()});
        return;
    }
    if (flags.version == true) {
        try std.io.getStdOut().writer().print("{s}", .{clap.Version_String()});
        return;
    }
    if (flags.debug_mode == true) {
        try std.io.getStdOut().writer().print("DEBUG MODE ENABLED\n\n", .{});
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
    const filestream = try std.fs.cwd().openFile(flags.input_filename.?, .{});
    const filecontents = try utils.Read_And_Allocate_File(filestream, global_allocator, 4096);
    defer global_allocator.free(filecontents);

    // lex and parse input file into individual tokens
    const lexed_tokens = try lex.Lexer(global_allocator, filecontents);
    defer global_allocator.free(lexed_tokens);
    defer tok.Destroy_Tokens_Contents(global_allocator, lexed_tokens);

    // [DEBUG OUTPUT] print lexed tokens
    if (flags.print_lexed_tokens) {
        std.debug.print("\nLexed tokens:\n", .{});
        tok.Print_Token_Array(lexed_tokens);
    }

    // expand macros
    const expanded_tokens = try pp.Preprocessor_Expansion(global_allocator, flags, &global_symbol_table, lexed_tokens);
    defer global_allocator.free(expanded_tokens);
    defer tok.Destroy_Tokens_Contents(global_allocator, expanded_tokens);

    // [DEBUG OUTPUT] print macro expanded tokens
    if (flags.print_expanded_tokens) {
        std.debug.print("\nExpanded tokens:\n", .{});
        tok.Print_Token_Array(expanded_tokens);
    }

    // start the code generation
    const rom = try codegen.Generate_Rom(global_allocator, flags, &global_symbol_table, expanded_tokens);
    defer global_allocator.free(rom);

    // create rom bytecode bin file relative to the current working directory
    // only perform this if an output name was specified with the "-o" flag
    if (flags.output_filename) |output_filename| {
        const rom_file = try std.fs.cwd().createFile(output_filename, std.fs.File.CreateFlags{});
        defer rom_file.close();
        try utils.Write_To_File(rom_file, rom);
    }

    // [DEBUG OUTPUT] print symbol hashtable
    if (flags.print_symbol_table) {
        global_symbol_table.Print();
    }

    // end benchmark
    const nanoseconds = timer.read();
    try std.io.getStdOut().writer().print("Compilation done in {}\n", .{std.fmt.fmtDuration(nanoseconds)});

    // print emit information
    if (flags.output_filename) |output_filename| {
        try std.io.getStdOut().writer().print("Written {} bytes to {s}\n", .{ rom.len, output_filename });
    }
}

// LICENSE:
// The entire Toy Assembly Suite Codebase is under the GNU General Public License Version 3.0
//
// PATCH NOTES:
// Assembler 0.1
//  -first stable functional release
// Assembler 0.2
//  -introduction of macros
// Assembler 0.3
//  -addresses are now 16-bit since a 32-bit address space
//   would be completely unrealistic, no one will use this language
//   long enough to question himself if he should use a jump near or
//   jump far...
// Assembler 0.4
//  -relative label referencing and anonymous labels introduced
// Assembler 0.4.1
//  -redesigned debug output flags
// Assembler 0.5
//  -debug mode metadata insertion introduced
// Assembler 0.5.1
//  -added "--noprint=[ARG]" flags
