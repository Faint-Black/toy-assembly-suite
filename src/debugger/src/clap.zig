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
    input_rom_filename: ?[]u8 = null,

    /// debug output flags
    log_instruction_opcode: bool = false,
    log_instruction_sideeffects: bool = false,

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
            } else if (std.mem.eql(u8, arg.?, "--log=all")) {
                result.log_instruction_opcode = true;
                result.log_instruction_sideeffects = true;
            } else if (std.mem.eql(u8, arg.?, "--log=opcodes")) {
                result.log_instruction_opcode = true;
            } else if (std.mem.eql(u8, arg.?, "--log=sideeffects")) {
                result.log_instruction_sideeffects = true;
            } else if (std.mem.eql(u8, arg.?, "--nolog=all")) {
                result.log_instruction_opcode = false;
                result.log_instruction_sideeffects = false;
            } else if (std.mem.eql(u8, arg.?, "--nolog=opcodes")) {
                result.log_instruction_opcode = false;
            } else if (std.mem.eql(u8, arg.?, "--nolog=sideeffects")) {
                result.log_instruction_sideeffects = false;
            } else {
                std.log.err("Unknown argument: \"{s}\"", .{arg.?});
                return error.BadArgument;
            }
        }

        if (result.binary_directory == null) {
            std.log.err("Binary directory could not be resolved!", .{});
            return error.BadArgument;
        }

        if (result.input_rom_filename == null) {
            result.input_rom_filename = try allocator.dupe(u8, "stdin");
        }

        return result;
    }

    pub fn Help_String() []const u8 {
        return 
        \\The toy assembler program.
        \\
        \\USAGE:
        \\$ ./debugger -i="../foobar.bin"
        \\$ ./debugger --input="../barbaz.rom" --log=all --nolog=sideeffects
        \\
        \\INFO FLAGS:
        \\-h, --help
        \\    Output this text.
        \\-v, --version
        \\    Output the version information of this program.
        \\
        \\CORE USAGE FLAGS:
        \\-i="path/to/rom.bin", --input="path/to/rom.bin"
        \\    Specify the input ROM file.
        \\
        \\INDIVIDUAL DEBUG OUTPUT FLAGS:
        \\--log=opcodes
        \\    Enable logging of each instruction being executed
        \\--log=sideeffects
        \\    Enable logging of the effect of the instruction on the machine
        \\
        \\--nolog=opcodes
        \\    Disable logging of each instruction being executed
        \\--nolog=sideeffects
        \\    Disable logging of the effect of the instruction on the machine
        \\
        \\GROUP DEBUG OUTPUT FLAGS:
        \\--log=all
        \\    Enable all logging flags
        \\
        \\--nolog=all
        \\    Disable all logging flags
        \\
        ;
    }

    pub fn Version_String() []const u8 {
        return 
        \\The toy debugger program
        \\Assembly suite version 1
        \\Debugger version 0.0
        \\
        ;
    }
};
