//=============================================================//
//                                                             //
//            COMMAND LINE ARGUMENTS PARSER                    //
//                                                             //
//   Responsible for setting the flags passed through the      //
//  command line terminal.                                     //
//                                                             //
//=============================================================//

const std = @import("std");
const warn = @import("shared").warn;

pub const Flags = struct {
    /// remember allocator for Deinit method
    allocator: std.mem.Allocator = undefined,

    /// core flags
    binary_directory: ?[]u8 = null,
    input_filename: ?[]u8 = null,
    output_filename: ?[]u8 = null,
    debug_mode: bool = false,

    /// debug output flags
    log_flags: bool = false,
    log_lexed_tokens: bool = false,
    log_stripped_tokens: bool = false,
    log_expanded_tokens: bool = false,
    log_symbol_table: bool = false,
    log_anon_labels: bool = false,
    log_rom_bytes: bool = false,

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

    pub fn Parse(allocator: std.mem.Allocator) !Flags {
        var result = Flags{};
        errdefer result.Deinit();
        result.allocator = allocator;

        // parsing loop
        var argv = try std.process.ArgIterator.initWithAllocator(allocator);
        defer argv.deinit();
        var arg: ?[:0]const u8 = argv.next();
        var argc: usize = 0;
        while (arg != null) : (argc += 1) {
            defer arg = argv.next();

            if (argc == 0) {
                result.binary_directory = try allocator.dupe(u8, arg.?);
            } else if (std.mem.eql(u8, arg.?, "-h") or std.mem.eql(u8, arg.?, "--help")) {
                result.help = true;
            } else if (std.mem.eql(u8, arg.?, "-v") or std.mem.eql(u8, arg.?, "--version")) {
                result.version = true;
            } else if (std.mem.startsWith(u8, arg.?, "-i=")) {
                result.input_filename = try allocator.dupe(u8, arg.?[3..]);
            } else if (std.mem.startsWith(u8, arg.?, "--input=")) {
                result.input_filename = try allocator.dupe(u8, arg.?[8..]);
            } else if (std.mem.startsWith(u8, arg.?, "-o=")) {
                result.output_filename = try allocator.dupe(u8, arg.?[3..]);
            } else if (std.mem.startsWith(u8, arg.?, "--output=")) {
                result.output_filename = try allocator.dupe(u8, arg.?[9..]);
            } else if (std.mem.eql(u8, arg.?, "-g") or std.mem.eql(u8, arg.?, "--debug")) {
                result.debug_mode = true;
            } else if (std.mem.eql(u8, arg.?, "--log=flags")) {
                result.log_flags = true;
            } else if (std.mem.eql(u8, arg.?, "--log=lexed")) {
                result.log_lexed_tokens = true;
            } else if (std.mem.eql(u8, arg.?, "--log=stripped")) {
                result.log_stripped_tokens = true;
            } else if (std.mem.eql(u8, arg.?, "--log=expanded")) {
                result.log_expanded_tokens = true;
            } else if (std.mem.eql(u8, arg.?, "--log=symbols")) {
                result.log_symbol_table = true;
            } else if (std.mem.eql(u8, arg.?, "--log=anonlabels")) {
                result.log_anon_labels = true;
            } else if (std.mem.eql(u8, arg.?, "--log=rom")) {
                result.log_rom_bytes = true;
            } else if (std.mem.eql(u8, arg.?, "--nolog=flags")) {
                result.log_flags = false;
            } else if (std.mem.eql(u8, arg.?, "--nolog=lexed")) {
                result.log_lexed_tokens = false;
            } else if (std.mem.eql(u8, arg.?, "--nolog=stripped")) {
                result.log_stripped_tokens = false;
            } else if (std.mem.eql(u8, arg.?, "--nolog=expanded")) {
                result.log_expanded_tokens = false;
            } else if (std.mem.eql(u8, arg.?, "--nolog=symbols")) {
                result.log_symbol_table = false;
            } else if (std.mem.eql(u8, arg.?, "--nolog=anonlabels")) {
                result.log_anon_labels = false;
            } else if (std.mem.eql(u8, arg.?, "--nolog=rom")) {
                result.log_rom_bytes = false;
            } else if (std.mem.eql(u8, arg.?, "--log=all")) {
                result.log_flags = true;
                result.log_lexed_tokens = true;
                result.log_stripped_tokens = true;
                result.log_expanded_tokens = true;
                result.log_symbol_table = true;
                result.log_anon_labels = true;
                result.log_rom_bytes = true;
            } else if (std.mem.eql(u8, arg.?, "--log=tokens")) {
                result.log_lexed_tokens = true;
                result.log_stripped_tokens = true;
                result.log_expanded_tokens = true;
            } else if (std.mem.eql(u8, arg.?, "--nolog=all")) {
                result.log_flags = false;
                result.log_lexed_tokens = false;
                result.log_stripped_tokens = false;
                result.log_expanded_tokens = false;
                result.log_symbol_table = false;
                result.log_anon_labels = false;
                result.log_rom_bytes = false;
            } else if (std.mem.eql(u8, arg.?, "--nolog=tokens")) {
                result.log_lexed_tokens = false;
                result.log_stripped_tokens = false;
                result.log_expanded_tokens = false;
            } else {
                warn.Error_Message("Unknown argument: \"{s}\"", .{arg.?});
                return error.BadArgument;
            }
        }

        if (result.binary_directory == null) {
            warn.Error_Message("Binary directory could not be resolved!", .{});
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
        \\$ ./assembler -i="samples/fibonacci.txt" -o="fib.bin"
        \\$ ./assembler --input="samples/alltokens.txt" --log=all -g --nolog=tokens
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
        \\-i="path/to/source.txt", --input="path/to/source.txt"
        \\    Perform the program operation on a text file.
        \\    You may leave this empty for a stdin input.
        \\-o="new/path/to/rom.bin", --output="new/path/to/rom.bin"
        \\    Define the output filename and filepath.
        \\    You may leave this empty for no file output.
        \\
        \\INDIVIDUAL DEBUG OUTPUT FLAGS:
        \\--log=flags
        \\    Enable print command line flags information
        \\--log=lexed
        \\    Enable print lexed tokens
        \\--log=stripped
        \\    Enable print stripped tokens
        \\--log=expanded
        \\    Enable print expanded tokens
        \\--log=symbols
        \\    Enable print symbol table
        \\--log=anonlabels
        \\    Enable print anonymous labels information
        \\--log=rom
        \\    Enable print rom dump
        \\
        \\--nolog=flags
        \\    Disable print command line flags information
        \\--nolog=lexed
        \\    Disable print lexed tokens
        \\--nolog=stripped
        \\    Disable print stripped tokens
        \\--nolog=expanded
        \\    Disable print expanded tokens
        \\--nolog=symbols
        \\    Disable print symbol table
        \\--nolog=anonlabels
        \\    Disable print anonymous labels information
        \\--nolog=rom
        \\    Disable print rom dump
        \\
        \\GROUP DEBUG OUTPUT FLAGS:
        \\--log=all
        \\    Enable all debug output flags
        \\--log=tokens
        \\    Enable lexed, stripped and expanded output flags
        \\
        \\--nolog=all
        \\    Disable all debug output flags
        \\--nolog=tokens
        \\    Disable lexed, stripped and expanded output flags
        \\
        ;
    }

    pub fn Version_String() []const u8 {
        return 
        \\The toy assembler program
        \\Assembly suite version 1
        \\Assembler version 0.0 (BETA BRANCH)
        \\
        ;
    }
};
