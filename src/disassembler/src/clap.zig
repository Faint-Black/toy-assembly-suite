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
    input_rom_filename: ?[]u8 = null,

    /// disassembly output flags
    log_header: bool = true,
    log_addresses: bool = true,
    log_rombytes: bool = true,
    log_instructions: bool = true,

    /// info flags
    help: bool = false,
    version: bool = false,

    pub fn Deinit(self: Flags) void {
        if (self.binary_directory) |memory|
            self.allocator.free(memory);
        if (self.input_rom_filename) |memory|
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
                result.input_rom_filename = try allocator.dupe(u8, arg.?[3..]);
            } else if (std.mem.startsWith(u8, arg.?, "--input=")) {
                result.input_rom_filename = try allocator.dupe(u8, arg.?[8..]);
            } else if (std.mem.startsWith(u8, arg.?, "--log=all")) {
                result.log_header = true;
                result.log_addresses = true;
                result.log_rombytes = true;
                result.log_instructions = true;
            } else if (std.mem.startsWith(u8, arg.?, "--nolog=all")) {
                result.log_header = false;
                result.log_addresses = false;
                result.log_rombytes = false;
                result.log_instructions = false;
            } else if (std.mem.startsWith(u8, arg.?, "--nolog=header")) {
                result.log_header = false;
            } else if (std.mem.startsWith(u8, arg.?, "--nolog=address")) {
                result.log_addresses = false;
            } else if (std.mem.startsWith(u8, arg.?, "--nolog=bytes")) {
                result.log_rombytes = false;
            } else if (std.mem.startsWith(u8, arg.?, "--nolog=instructions")) {
                result.log_instructions = false;
            } else {
                warn.Error_Message("Unknown argument: \"{s}\"", .{arg.?});
                return error.BadArgument;
            }
        }

        if (result.binary_directory == null) {
            warn.Error_Message("Binary directory could not be resolved!", .{});
            return error.BadArgument;
        }

        if (result.input_rom_filename == null) {
            result.input_rom_filename = try allocator.dupe(u8, "stdin");
        }

        return result;
    }

    pub fn Help_String() []const u8 {
        return 
        \\The toy disassembler program.
        \\
        \\USAGE:
        \\$ ./disassembler -i="rom.bin"
        \\$ ./debugger --input="../foo.rom"
        \\
        \\INFO FLAGS:
        \\-h, --help
        \\    Output this text.
        \\-v, --version
        \\    Output the version information of this program.
        \\
        \\CORE USAGE FLAGS:
        \\-i="path/to/rom.bin", --input="path/to/rom.bin"
        \\    Specify the input ROM file. Default is stdin.
        \\
        \\OUTPUT STYLE FLAGS:
        \\--nolog=header
        \\    Disable the printing of the humanly readable header information.
        \\--nolog=address
        \\    Disable the printing of the ROM memory addresses to the disassembly output.
        \\--nolog=bytes
        \\    Disable the printing of the ROM byte contents to the disassembly output.
        \\--nolog=instructions
        \\    Disable the printing of the disassembled instructions to the disassembly output.
        \\
        \\GROUP DEBUG OUTPUT FLAGS:
        \\--log=all
        \\    Enable all debug output flags
        \\
        \\--nolog=all
        \\    Disable all debug output flags
        \\
        ;
    }

    pub fn Version_String() []const u8 {
        return 
        \\The toy disassembler program
        \\Assembly suite version 1
        \\Disassembler version 0.0 (BETA BRANCH)
        \\
        ;
    }
};
