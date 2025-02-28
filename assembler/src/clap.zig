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
    /// remember allocator for Deinit
    allocator: std.mem.Allocator = undefined,

    /// flags
    binary_directory: ?[]u8 = null,
    input_filename: ?[]u8 = null,
    output_filename: ?[]u8 = null,
    debug_mode: bool = false,

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
        } else if (std.mem.eql(u8, arg.?, "-d") or std.mem.eql(u8, arg.?, "--debug")) {
            result.debug_mode = true;
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
    \\Examples of usage:
    \\$ ./assembler -i "samples/fibonacci.txt" -o "fib.bin"
    \\$ ./assembler -i "samples/alltokens.txt" -d
    \\
    \\-h, --help
    \\    Output this text.
    \\-v, --version
    \\    Output the version of the program.
    \\-d, --debug
    \\    Enable debug mode.
    \\-i "path/to/source.txt", --input "path/to/source.txt"
    \\    Perform the program operation on a text file.
    \\-o "new/path/to/rom.bin", --output "new/path/to/rom.bin"
    \\    Define the output filename and filepath.
    \\    You may leave this empty for no file output.
    \\
    ;
}

pub fn Version_String() []const u8 {
    return 
    \\The toy assembler program
    \\Assembly suite version 1
    \\Assembler version 0.3.0
    \\
    ;
}
