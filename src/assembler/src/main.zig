//=============================================================//
//                                                             //
//                           MAIN                              //
//                                                             //
//   Patch notes and license details at the bottom.            //
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

pub fn main() void {
    // begin benchmark
    var timer = std.time.Timer.start() catch {
        warn.Error_Message("UPSTREAM: could not begin benchmark timer!", .{});
        return;
    };

    // use DebugAllocator on debug mode
    // use SmpAllocator on release mode
    var debug_struct_allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_struct_allocator.deinit();
    var global_allocator: std.mem.Allocator = if (builtin.mode == .Debug) debug_struct_allocator.allocator() else std.heap.smp_allocator;

    // keep track of identifiers through all steps
    var global_symbol_table = sym.SymbolTable.Init(global_allocator);
    defer global_symbol_table.Deinit();

    // command-line flags, filenames and filepath specifications
    const flags = clap.Flags.Parse(global_allocator) catch {
        warn.Error_Message("UPSTREAM: could not parse command line flags!", .{});
        return;
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
    const filestream = std.fs.cwd().openFile(flags.input_filename.?, .{}) catch {
        warn.Error_Message("UPSTREAM: could not open file \"{?s}\"!", .{flags.input_filename});
        return;
    };
    const filecontents = utils.Read_And_Allocate_File(filestream, global_allocator, 4096) catch {
        warn.Error_Message("UPSTREAM: could not read or allocate file contents!", .{});
        return;
    };
    defer global_allocator.free(filecontents);

    // lex and parse input file into individual tokens
    const lexed_tokens = lex.Lexer(global_allocator, filecontents) catch {
        warn.Error_Message("UPSTREAM: lexing failed!", .{});
        return;
    };
    defer global_allocator.free(lexed_tokens);
    defer tok.Destroy_Tokens_Contents(global_allocator, lexed_tokens);

    // [DEBUG OUTPUT] print lexed tokens
    if (flags.print_lexed_tokens) {
        std.debug.print("\nLexed tokens:\n", .{});
        tok.Print_Token_Array(lexed_tokens);
    }

    // expand macros
    const expanded_tokens = pp.Preprocessor_Expansion(global_allocator, flags, &global_symbol_table, lexed_tokens) catch {
        warn.Error_Message("UPSTREAM: macro expansion failed!", .{});
        return;
    };
    defer global_allocator.free(expanded_tokens);
    defer tok.Destroy_Tokens_Contents(global_allocator, expanded_tokens);

    // [DEBUG OUTPUT] print macro expanded tokens
    if (flags.print_expanded_tokens) {
        std.debug.print("\nExpanded tokens:\n", .{});
        tok.Print_Token_Array(expanded_tokens);
    }

    // start the code generation
    const rom = codegen.Generate_Rom(global_allocator, flags, &global_symbol_table, expanded_tokens) catch {
        warn.Error_Message("UPSTREAM: rom bytecode generation failed!", .{});
        return;
    };
    defer global_allocator.free(rom);

    // create rom bytecode bin file relative to the current working directory
    // only perform this if an output name was specified with the "-o" flag
    if (flags.output_filename) |output_filename| {
        const rom_file = std.fs.cwd().createFile(output_filename, std.fs.File.CreateFlags{}) catch {
            warn.Error_Message("UPSTREAM: failed to create rom file!", .{});
            return;
        };
        defer rom_file.close();
        utils.Write_To_File(rom_file, rom) catch {
            warn.Error_Message("UPSTREAM: failed to write to created rom file!", .{});
            return;
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
// Assembler 0.6
//  -repeat unwrapper instroduced
// Assembler 1.0
//  -(probably) stable release for practical use
// Assembler 1.1
//  -changed CLAP arguments style
// Assembler 1.2
//  -added the STRIDE instruction
// Assembler 1.3
//  -changed the ROM dump debug print output format
// Assembler 1.4
//  -release error handling
