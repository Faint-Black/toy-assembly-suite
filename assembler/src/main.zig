//=============================================================//
//                                                             //
//                           MAIN                              //
//                                                             //
//   Compiled with Zig 0.14.0-dev (EXPERIMENTAL DEV BUILD).    //
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

// TODO: on march 3rd Zig 0.14 will be fully released, update codebase accordingly.
// TODO: implement .repeat n and .endrepeat
// TODO: implement (run-time) visibility toggles for debug information
// TODO: clean the lone newline token created by macros
// TODO: big design decision: set address bytecode size to 16-bit

/// EXECUTION MODEL:
///
/// 1st step, turn the raw input string into usable tokens.
/// lex: [input file string] -> [lexed tokens]
///
/// 2nd step, remove the preprocessor definitions and add them
/// to the global identifier symbol table.
/// strip: [lexed tokens] -> [stripped tokens]
///
/// 3rd step, if any preprocessor identifier is found, expand
/// them accordingly.
/// expand: [stripped tokens] -> [expanded tokens]
///
/// 4th step, now with the tokens in their finalized state, start
/// the actual vmachine bytecode generation.
/// codegen: [expanded tokens] -> [rom bytecode]
///
/// 5th and final step, output the bytecode as a binary file.
/// emit: [rom bytecode] -> [rom file]
pub fn main() !void {
    // general purpose allocator will be used for all functions
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const global_allocator = gpa.allocator();

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

    // load file into a newly allocated buffer
    const filestream = try std.fs.cwd().openFile(flags.input_filename.?, .{});
    const filecontents = try utils.Read_And_Allocate_File(filestream, global_allocator, 4096);
    defer global_allocator.free(filecontents);

    // lex and parse input file into individual tokens
    const lexed_tokens = try lex.Lexer(global_allocator, filecontents);
    defer global_allocator.free(lexed_tokens);
    defer tok.Destroy_Tokens_Contents(global_allocator, lexed_tokens);

    // expand macros
    const expanded_tokens = try pp.Preprocessor_Expansion(global_allocator, &global_symbol_table, lexed_tokens);
    defer global_allocator.free(expanded_tokens);
    defer tok.Destroy_Tokens_Contents(global_allocator, expanded_tokens);

    // start the code generation
    const rom = try codegen.Generate_Rom(global_allocator, &global_symbol_table, expanded_tokens);
    defer global_allocator.free(rom);

    // create rom bytecode bin file relative to the current working directory
    // only perform this if an output name was specified with the "-o" flag
    if (flags.output_filename) |output_filename| {
        const rom_file = try std.fs.cwd().createFile(output_filename, std.fs.File.CreateFlags{});
        defer rom_file.close();
        try utils.Write_To_File(rom_file, rom);
    }

    // debug information printing
    std.debug.print("\nSymbol table data:", .{});
    global_symbol_table.Print();

    // debug information printing
    std.debug.print("\nROM dump:\n", .{});
    for (rom, 0..) |byte, i|
        std.debug.print("{X:0>8} - 0x{X:0>2}\n", .{ i, byte });
}
