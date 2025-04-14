//=============================================================//
//                                                             //
//                       CODE ANALYZER                         //
//                                                             //
//   Responsible for checking and warning user mistakes.       //
//  Consider this the "compiler warnings" part of the          //
//  assembler, only applies to the generated ROM though.       //
//                                                             //
//=============================================================//

const std = @import("std");
const utils = @import("shared").utils;
const specs = @import("shared").specifications;
const tok = @import("token.zig");
const sym = @import("symbol.zig");
const clap = @import("clap.zig");
const warn = @import("shared").warn;

const AnalysisResults = struct {
    is_stride_defined: bool = false,
    is_indexed_defined: bool = false,
    is_break_defined: bool = false,
    last_instruction: specs.Opcode = undefined,
};

pub fn Analyze_Rom(rom: []u8) !void {
    const status = Step_Through(rom);

    if (rom.len >= specs.bytelen.rom) {
        warn.Error_Message("created a rom file larger than the allowed 0x{} memory space!", .{specs.bytelen.rom});
        return error.CompilationError;
    }
    if (status.last_instruction == .JSR_ADDR) {
        warn.Error_Message("code cannot have a Jump To Subroutine as the last instruction!", .{});
        return error.CompilationError;
    }
    if (status.is_stride_defined == false and status.is_indexed_defined == true) {
        warn.Warn_Message("indexing instructions have been found but no STRIDE has been defined! Execution of this ROM is garanteed to cause undefined behavior.", .{});
    }
    if (status.is_break_defined == false) {
        warn.Warn_Message("no BRK has been defined anywhere! Execution of this ROM is garanteed to run forever or until a fatal error occurs.", .{});
    }
}

//-------------------------------------------------------------//
// STATIC PRIVATE FUNCTIONS                                    //
//-------------------------------------------------------------//

fn Step_Through(rom: []u8) AnalysisResults {
    var results = AnalysisResults{};
    const rom_header = specs.Header.Parse_From_Byte_Array(rom[0..16].*);

    // skip header and data segment, only analyze instructions.
    var PC: u16 = rom_header.entry_point;
    while (PC < rom.len) {
        const opcode_enum: specs.Opcode = @enumFromInt(rom[PC]);
        results.last_instruction = opcode_enum;

        // skip debug metadata bytes
        if (rom_header.debug_mode and opcode_enum == .DEBUG_METADATA_SIGNAL) {
            const metadata_type: specs.DebugMetadataType = @enumFromInt(rom[PC + 1]);
            const metadata_bytelen: u16 = @truncate(metadata_type.Metadata_Length(rom[PC..]) catch 0);
            PC += metadata_bytelen;
            continue;
        }

        // check instructions
        switch (opcode_enum) {
            .STRIDE_LIT => {
                results.is_stride_defined = true;
            },
            .LDA_ADDR_X, .LDA_ADDR_Y => {
                results.is_indexed_defined = true;
            },
            .BRK => {
                results.is_break_defined = true;
            },
            else => {},
        }

        // advance counter
        PC += opcode_enum.Instruction_Byte_Length();
    }

    return results;
}
