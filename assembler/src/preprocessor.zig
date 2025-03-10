//=============================================================//
//                                                             //
//                       PRE-PROCESSOR                         //
//                                                             //
//   Responsible for dealing with the stripping and expansion  //
//  of preprocessor definitions, like macros and repeats.      //
//                                                             //
//=============================================================//

const std = @import("std");
const utils = @import("utils.zig");
const tok = @import("token.zig");
const sym = @import("symbol.zig");
const clap = @import("clap.zig");

/// Removes, replaces and expands preprocessor instructions,
/// like macros.
pub fn Preprocessor_Expansion(allocator: std.mem.Allocator, flags: clap.Flags, symTable: *sym.SymbolTable, lexedTokens: []const tok.Token) ![]tok.Token {
    // removes preprocessor definitions and adds them to the global symbol table.
    // this token array is a complete allocated and intermediary copy
    // and must be completely destroyed before this function exits
    const stripped_tokens = try First_Pass(allocator, symTable, lexedTokens);
    defer allocator.free(stripped_tokens);
    defer tok.Destroy_Tokens_Contents(allocator, stripped_tokens);

    // [DEBUG OUTPUT] print the resulting stripped tokens
    if (flags.print_stripped_tokens) {
        std.debug.print("\nStripped tokens:\n", .{});
        tok.Print_Token_Array(stripped_tokens);
    }

    // expands macro identifiers and returns a new token array.
    // this token array is a complete allocated copy
    const expanded_tokens = try Second_Pass(allocator, symTable, stripped_tokens);
    return expanded_tokens;
}

//-------------------------------------------------------------//
// STATIC PRIVATE FUNCTIONS                                    //
//-------------------------------------------------------------//

/// Removes all the macro definition tokens and adds them to the symbol registry,
/// also adds dummy LABEL symbols which enable forward referencing.
/// .repeat macros are the current exception since they are nameless and
/// unwrapped on the spot.
fn First_Pass(allocator: std.mem.Allocator, symTable: *sym.SymbolTable, tokens: []const tok.Token) ![]tok.Token {
    // this step only adds the dummy label entries to the symbol table,
    // no removal or allocation necessary.
    try Add_Labels(allocator, symTable, tokens);

    const removed_macros = try Remove_Macros(allocator, symTable, tokens);
    defer allocator.free(removed_macros);
    defer tok.Destroy_Tokens_Contents(allocator, removed_macros);

    const removed_defines = try Remove_Defines(allocator, symTable, removed_macros);
    return removed_defines;
}

/// unwraps the macros identifiers into a new token array
fn Second_Pass(allocator: std.mem.Allocator, symTable: *sym.SymbolTable, tokens: []const tok.Token) ![]tok.Token {
    const unwrapped_repeats = try Unwrap_Repeats(allocator, tokens);
    defer allocator.free(unwrapped_repeats);
    defer tok.Destroy_Tokens_Contents(allocator, unwrapped_repeats);

    // CAUTION: Do not defer deallocate!
    const unwrapped_macros = try Unwrap_Macros(allocator, symTable, unwrapped_repeats);
    // the function below does *not* create a token array copy, so the memory
    // still belongs to the previous function.
    const unwrapped_defines = try Unwrap_Defines(allocator, symTable, unwrapped_macros);

    return unwrapped_defines;
}

/// dummy label creation, for forward referencing purposes
fn Add_Labels(allocator: std.mem.Allocator, symTable: *sym.SymbolTable, tokens: []const tok.Token) !void {
    for (tokens) |token| {
        if (token.tokType == .LABEL) {
            const label_symbol = sym.Symbol{ .name = try utils.Copy_Of_ConstString(allocator, token.identKey.?), .value = .{ .label = tok.Token.Init() } };
            try symTable.Add(label_symbol);
        }
    }
}

fn Remove_Macros(allocator: std.mem.Allocator, symTable: *sym.SymbolTable, tokens: []const tok.Token) ![]tok.Token {
    var token_vector = std.ArrayList(tok.Token).init(allocator);
    defer token_vector.deinit();
    try token_vector.ensureTotalCapacity(tokens.len);

    var macro_vector = std.ArrayList(tok.Token).init(allocator);
    defer macro_vector.deinit();

    var skip_newline: bool = false;
    var build_macro_mode: bool = false;
    for (tokens) |token| {
        if (skip_newline) {
            skip_newline = false;
            if (token.tokType == .LINEFINISH)
                continue;
        }

        if (token.tokType == .MACRO) {
            if (build_macro_mode == true) {
                std.log.err("Cannot define a macro inside another macro!", .{});
                return error.BadMacro;
            }
            build_macro_mode = true;
            continue;
        }

        if (token.tokType == .ENDMACRO) {
            if (build_macro_mode == false) {
                std.log.err("No macro to end!", .{});
                return error.BadMacro;
            }
            build_macro_mode = false;
            continue;
        }

        // when you forget to add .endmacro at the end of a definition
        if (token.tokType == .ENDOFFILE and build_macro_mode == true) {
            std.log.err("Found EOF while building macro!", .{});
            return error.BadMacro;
        }

        // add macro tokens to token buffer, flush signal is a .endmacro token
        if (build_macro_mode) {
            try macro_vector.append(try token.Copy(allocator));
            continue;
        }

        // flush built macro to symbol table
        if (build_macro_mode == false and macro_vector.items.len > 0) {
            // validate proper syntax
            // .macro, {"name", $, CONTENTS }, .endrepeat, $
            if (macro_vector.items.len < 3)
                return error.MissingMacroContents;
            if (macro_vector.items[0].identKey == null)
                return error.NamelessMacro;
            if (macro_vector.items[1].tokType != .LINEFINISH)
                return error.BadName;

            // discard macro name and newline tokens, respectively
            const macro_name = macro_vector.orderedRemove(0).identKey.?;
            _ = macro_vector.orderedRemove(0);

            var macro_symbol: sym.Symbol = undefined;
            macro_symbol.name = macro_name;
            macro_symbol.value = .{ .macro = try macro_vector.toOwnedSlice() };
            try symTable.Add(macro_symbol);

            build_macro_mode = false;
            skip_newline = true;
            continue;
        }

        try token_vector.append(try token.Copy(allocator));
    }

    if (macro_vector.items.len > 0) {
        std.log.err("Unflushed macro!", .{});
        return error.BadMacro;
    }

    return token_vector.toOwnedSlice();
}

fn Remove_Defines(allocator: std.mem.Allocator, symTable: *sym.SymbolTable, tokens: []const tok.Token) ![]tok.Token {
    var token_vector = std.ArrayList(tok.Token).init(allocator);
    defer token_vector.deinit();
    try token_vector.ensureTotalCapacity(tokens.len);

    // [0] -> define name
    // [1] -> define contents
    var define_buffer: [2]tok.Token = .{tok.Token.Init()} ** 2;
    var define_count: usize = 0;

    var build_define_mode: bool = false;
    for (tokens) |token| {
        if (token.tokType == .DEFINE) {
            build_define_mode = true;
            continue;
        }
        if (token.tokType == .LINEFINISH) {
            build_define_mode = false;
        }

        if (build_define_mode) {
            try utils.Append_Element_To_Buffer(tok.Token, &define_buffer, &define_count, token);
            continue;
        }

        if (build_define_mode == false and define_count > 0) {
            // validate proper syntax
            // .define, { "name", TOKEN }, $
            if (define_count < 2)
                return error.BadDefine;
            if (define_buffer[0].identKey == null)
                return error.NamelessDefine;

            const define_symbol = sym.Symbol{
                .name = try utils.Copy_Of_ConstString(allocator, define_buffer[0].identKey.?),
                .value = .{ .define = try define_buffer[1].Copy(allocator) },
            };
            try symTable.Add(define_symbol);

            // clear buffer
            define_count = 0;

            // skip newline
            continue;
        }

        try token_vector.append(try token.Copy(allocator));
    }

    return token_vector.toOwnedSlice();
}

fn Unwrap_Repeats(allocator: std.mem.Allocator, tokens: []const tok.Token) ![]tok.Token {
    var token_vector = std.ArrayList(tok.Token).init(allocator);
    defer token_vector.deinit();
    try token_vector.ensureTotalCapacity(tokens.len);

    var repeat_vector = std.ArrayList(tok.Token).init(allocator);
    defer repeat_vector.deinit();

    var skip_newline: bool = false;
    var build_repeat_mode: bool = false;
    for (tokens) |token| {
        // ignore lone newline after .endrepeat token
        if (skip_newline) {
            skip_newline = false;
            if (token.tokType == .LINEFINISH)
                continue;
        }

        if (token.tokType == .REPEAT) {
            build_repeat_mode = true;
            continue;
        }
        if (token.tokType == .ENDREPEAT) {
            build_repeat_mode = false;
            skip_newline = true;

            // validate proper syntax
            // .repeat { LIT=n, $, CONTENTS } .endrepeat $
            if (repeat_vector.items.len < 2)
                return error.EmptyRepeatContents;
            if (repeat_vector.items[0].tokType != .LITERAL)
                return error.MissingRepeatLiteralParameter;
            if (repeat_vector.items[1].tokType != .LINEFINISH)
                return error.MissingNewlineAtRepeat;

            // append repeat contents n times
            const repeat_n = repeat_vector.items[0].value;
            for (0..repeat_n) |_|
                try token_vector.appendSlice(repeat_vector.items[2..]);

            // clear repeat tokens vector and repeat the process
            tok.Destroy_Tokens_Contents(allocator, repeat_vector.items);
            repeat_vector.clearRetainingCapacity();
            continue;
        }
        if (build_repeat_mode) {
            try repeat_vector.append(try token.Copy(allocator));
            continue;
        }

        try token_vector.append(try token.Copy(allocator));
    }

    return token_vector.toOwnedSlice();
}

fn Unwrap_Macros(allocator: std.mem.Allocator, symTable: *sym.SymbolTable, tokens: []const tok.Token) ![]tok.Token {
    var token_vector = std.ArrayList(tok.Token).init(allocator);
    defer token_vector.deinit();

    var last_macro_tokentype: tok.TokenType = .UNDEFINED;
    for (tokens) |token| {
        if (token.tokType == .IDENTIFIER) {
            const symbol = symTable.Get(token.identKey);
            // pay no mind to missing identifiers
            if (symbol == null) {
                try token_vector.append(try token.Copy(allocator));
                continue;
            }

            switch (symbol.?.value) {
                .macro => {
                    // append macro contents, one token at a time
                    for (symbol.?.value.macro) |macroTok| {
                        try token_vector.append(try macroTok.Copy(allocator));
                        last_macro_tokentype = macroTok.tokType;
                    }
                    continue;
                },
                else => {},
            }
        }
        // skip addition of unecessary newline token
        if (token.tokType == .LINEFINISH and last_macro_tokentype == .LINEFINISH)
            continue;
        last_macro_tokentype = .UNDEFINED;

        try token_vector.append(try token.Copy(allocator));
    }

    return token_vector.toOwnedSlice();
}

/// since its only changes one token at a time, this function modifies the identifier tokens
/// inplace with no needs for token vectors
fn Unwrap_Defines(allocator: std.mem.Allocator, symTable: *sym.SymbolTable, tokens: []tok.Token) ![]tok.Token {
    for (tokens) |*token| {
        if (token.tokType == .IDENTIFIER) {
            const symbol = symTable.Get(token.identKey);
            // pay no mind to missing identifiers
            if (symbol == null)
                continue;

            switch (symbol.?.value) {
                .define => {
                    // substitute it inplace
                    token.Deinit(allocator);
                    token.* = try symbol.?.value.define.Copy(allocator);
                    continue;
                },
                else => {},
            }
        }
    }

    return tokens;
}
