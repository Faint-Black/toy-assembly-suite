//=============================================================//
//                                                             //
//            COMMAND LINE ARGUMENTS PARSER                    //
//                                                             //
//   Responsible for setting the flags passed through the      //
//  command line terminal.                                     //
//                                                             //
//=============================================================//

const std = @import("std");

pub const Flags = struct {
    /// remember allocator for Deinit method
    allocator: std.mem.Allocator = undefined,

    /// core flags
    binary_directory: ?[]u8 = null,
    input_filename: ?[]u8 = null,
    output_filename: ?[]u8 = null,
    debug_mode: bool = false,

    /// debug output flags
    print_flags: bool = false,
    print_lexed_tokens: bool = false,
    print_stripped_tokens: bool = false,
    print_expanded_tokens: bool = false,
    print_symbol_table: bool = false,
    print_anon_labels: bool = false,
    print_rom_bytes: bool = false,

    /// info flags
    help: bool = false,
    version: bool = false,

    pub fn Deinit(self: Flags) void {
        if (self.input_filename) |memory|
            self.allocator.free(memory);
        if (self.binary_directory) |memory|
            self.allocator.free(memory);
        if (self.output_filename) |memory|
            self.allocator.free(memory);
    }
};

pub fn Parse_Arguments(allocator: std.mem.Allocator) !Flags {
    var result = Flags{};
    result.allocator = allocator;

    var argv = try std.process.ArgIterator.initWithAllocator(allocator);
    var argc: usize = 0;
    defer argv.deinit();
    errdefer result.Deinit();

    var expecting_input_filename = false;
    var expecting_output_filename = false;
    var arg = argv.next();
    while (true) : (argc += 1) {
        if (arg == null)
            break;
        defer arg = argv.next();

        if (argc == 0) {
            result.binary_directory = try allocator.dupe(u8, arg.?);
            continue;
        }

        if (expecting_input_filename) {
            result.input_filename = try allocator.dupe(u8, arg.?);
            expecting_input_filename = false;
        } else if (expecting_output_filename) {
            result.output_filename = try allocator.dupe(u8, arg.?);
            expecting_output_filename = false;
        } else if (std.mem.eql(u8, arg.?, "-h") or std.mem.eql(u8, arg.?, "--help")) {
            result.help = true;
        } else if (std.mem.eql(u8, arg.?, "-v") or std.mem.eql(u8, arg.?, "--version")) {
            result.version = true;
        } else if (std.mem.eql(u8, arg.?, "-i") or std.mem.eql(u8, arg.?, "--input")) {
            expecting_input_filename = true;
        } else if (std.mem.eql(u8, arg.?, "-o") or std.mem.eql(u8, arg.?, "--output")) {
            expecting_output_filename = true;
        } else if (std.mem.eql(u8, arg.?, "-g") or std.mem.eql(u8, arg.?, "--debug")) {
            result.debug_mode = true;
        } else if (std.mem.eql(u8, arg.?, "--print=all")) {
            result.print_flags = true;
            result.print_lexed_tokens = true;
            result.print_stripped_tokens = true;
            result.print_expanded_tokens = true;
            result.print_symbol_table = true;
            result.print_anon_labels = true;
            result.print_rom_bytes = true;
        } else if (std.mem.eql(u8, arg.?, "--print=flags")) {
            result.print_flags = true;
        } else if (std.mem.eql(u8, arg.?, "--print=lexed")) {
            result.print_lexed_tokens = true;
        } else if (std.mem.eql(u8, arg.?, "--print=stripped")) {
            result.print_stripped_tokens = true;
        } else if (std.mem.eql(u8, arg.?, "--print=expanded")) {
            result.print_expanded_tokens = true;
        } else if (std.mem.eql(u8, arg.?, "--print=symbols")) {
            result.print_symbol_table = true;
        } else if (std.mem.eql(u8, arg.?, "--print=anonlabels")) {
            result.print_anon_labels = true;
        } else if (std.mem.eql(u8, arg.?, "--print=rom")) {
            result.print_rom_bytes = true;
        } else if (std.mem.eql(u8, arg.?, "--noprint=all")) {
            result.print_flags = false;
            result.print_lexed_tokens = false;
            result.print_stripped_tokens = false;
            result.print_expanded_tokens = false;
            result.print_symbol_table = false;
            result.print_anon_labels = false;
            result.print_rom_bytes = false;
        } else if (std.mem.eql(u8, arg.?, "--noprint=flags")) {
            result.print_flags = false;
        } else if (std.mem.eql(u8, arg.?, "--noprint=lexed")) {
            result.print_lexed_tokens = false;
        } else if (std.mem.eql(u8, arg.?, "--noprint=stripped")) {
            result.print_stripped_tokens = false;
        } else if (std.mem.eql(u8, arg.?, "--noprint=expanded")) {
            result.print_expanded_tokens = false;
        } else if (std.mem.eql(u8, arg.?, "--noprint=symbols")) {
            result.print_symbol_table = false;
        } else if (std.mem.eql(u8, arg.?, "--noprint=anonlabels")) {
            result.print_anon_labels = false;
        } else if (std.mem.eql(u8, arg.?, "--noprint=rom")) {
            result.print_rom_bytes = false;
        } else {
            std.log.err("Unknown argument: \"{s}\"", .{arg.?});
            return error.BadArgument;
        }
    }

    if (expecting_input_filename == true) {
        std.log.err("No input filename given!", .{});
        return error.BadArgument;
    }

    if (expecting_output_filename == true) {
        std.log.err("No output filename given!", .{});
        return error.BadArgument;
    }

    if (result.binary_directory == null) {
        std.log.err("Binary directory could not be resolved!", .{});
        return error.BadArgument;
    }

    if (result.input_filename == null) {
        result.input_filename = try allocator.dupe(u8, "stdin");
    }

    return result;
}

pub fn Help_String() []const u8 {
    return 
    \\The toy assembler program.
    \\
    \\USAGE:
    \\$ ./assembler -i "samples/fibonacci.txt" -o "fib.bin"
    \\$ ./assembler -i "samples/alltokens.txt" --print=all -g
    \\
    \\INFO FLAGS:
    \\-h, --help
    \\    Output this text.
    \\-v, --version
    \\    Output the version information of this program.
    \\
    \\CORE USAGE FLAGS:
    \\-g, --debug
    \\    Enable rom debug metadata insertion. (EXPERIMENTAL)
    \\-i "path/to/source.txt", --input "path/to/source.txt"
    \\    Perform the program operation on a text file.
    \\-o "new/path/to/rom.bin", --output "new/path/to/rom.bin"
    \\    Define the output filename and filepath.
    \\    You may leave this empty for no file output.
    \\
    \\DEBUG OUTPUT FLAGS:
    \\--print=all
    \\    Enable all debug output flags
    \\--print=flags
    \\    Enable print command line flags information
    \\--print=lexed
    \\    Enable print lexed tokens
    \\--print=stripped
    \\    Enable print stripped tokens
    \\--print=expanded
    \\    Enable print expanded tokens
    \\--print=symbols
    \\    Enable print symbol table
    \\--print=anonlabels
    \\    Enable print anonymous labels information
    \\--print=rom
    \\    Enable print rom dump
    \\
    \\--noprint=all
    \\    Disable all debug output flags
    \\--noprint=flags
    \\    Disable print command line flags information
    \\--noprint=lexed
    \\    Disable print lexed tokens
    \\--noprint=stripped
    \\    Disable print stripped tokens
    \\--noprint=expanded
    \\    Disable print expanded tokens
    \\--noprint=symbols
    \\    Disable print symbol table
    \\--noprint=anonlabels
    \\    Disable print anonymous labels information
    \\--noprint=rom
    \\    Disable print rom dump
    ;
}

pub fn Version_String() []const u8 {
    return 
    \\The toy assembler program
    \\Assembly suite version 1
    \\Assembler version 0.5.1
    \\
    ;
}
