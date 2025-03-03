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
/// also adds dummy LABEL symbols which enable forward referencing
fn First_Pass(allocator: std.mem.Allocator, symTable: *sym.SymbolTable, tokens: []const tok.Token) ![]tok.Token {
    var token_vector = std.ArrayList(tok.Token).init(allocator);
    defer token_vector.deinit();
    var macro_vector = std.ArrayList(tok.Token).init(allocator);
    defer macro_vector.deinit();

    var building_mode: tok.TokenType = .UNDEFINED;
    for (tokens) |token| {
        // dummy label creation, for forward referencing purposes
        if (token.tokType == .LABEL) {
            const label_symbol = sym.Symbol{ .name = try utils.Copy_Of_ConstString(allocator, token.identKey.?), .value = .{ .label = tok.Token.Init() } };
            try symTable.*.Add(label_symbol);
        }

        // macro-begin and macro-end signal tokens
        if (token.tokType == .MACRO) {
            if (building_mode == .MACRO) {
                std.log.err("Cannot define a macro inside another macro!", .{});
                return error.BadMacro;
            }
            building_mode = .MACRO;
            continue;
        }
        if (token.tokType == .ENDMACRO) {
            if (building_mode == .ENDMACRO) {
                std.log.err("No macro to end!", .{});
                return error.BadMacro;
            }
            building_mode = .ENDMACRO;
            continue;
        }

        // single token macro signal token
        if (token.tokType == .DEFINE) {
            building_mode = .DEFINE;
            continue;
        }

        // when you forget to add .endmacro at the end of a definition
        if (token.tokType == .ENDOFFILE and building_mode == .MACRO) {
            std.log.err("Found EOF while building macro!", .{});
            return error.BadMacro;
        }

        // add macro tokens to token buffer, flush signal is a .endmacro token
        if (building_mode == .MACRO) {
            try macro_vector.append(try token.Copy(allocator));
            continue;
        }

        // add define tokens to token buffer, flush signal is a newline token
        if (building_mode == .DEFINE)
            try macro_vector.append(try token.Copy(allocator));

        // flush built macro to symbol table
        if (building_mode == .ENDMACRO and macro_vector.items.len > 0) {
            // assert if macro was given a valid name
            if (macro_vector.items[0].identKey == null)
                return error.NamelessMacro;
            // assert if macro has a newline after the macro name
            if (macro_vector.items[1].tokType != .LINEFINISH)
                return error.BadName;

            // discard macro name and newline tokens, respectively
            const macro_name = macro_vector.orderedRemove(0).identKey.?;
            _ = macro_vector.orderedRemove(0);

            var macro_symbol: sym.Symbol = undefined;
            macro_symbol.name = macro_name;
            macro_symbol.value = .{ .macro = try macro_vector.toOwnedSlice() };
            try symTable.*.Add(macro_symbol);
        }
        if (building_mode == .ENDMACRO) {
            building_mode = .UNDEFINED;
            // skip addition of unecessary newline after the ".endmacro"
            if (token.tokType == .LINEFINISH)
                continue;
        }

        // flush built define to symbol table when encountering a linefinish
        if (building_mode == .DEFINE and token.tokType == .LINEFINISH) {
            // assert if define was given a valid name
            if (macro_vector.items[0].identKey == null)
                return error.NamelessDefine;
            // assert if define has a lone, non linefinish token after the macro name
            if (macro_vector.items[1].tokType == .LINEFINISH)
                return error.EmptyDefine;
            // assert if define has a lone, non linefinishing token after the macro name
            if (macro_vector.items[2].tokType != .LINEFINISH)
                return error.MultipleTokensInDefine;

            // only pick the data we need
            const define_name = macro_vector.items[0].identKey.?;
            const define_contents = macro_vector.items[1];
            var define_symbol: sym.Symbol = undefined;
            define_symbol.name = try utils.Copy_Of_ConstString(allocator, define_name);
            define_symbol.value = .{ .define = try define_contents.Copy(allocator) };
            try symTable.*.Add(define_symbol);

            // and discard the rest
            for (macro_vector.items) |define_token|
                define_token.Deinit(allocator);
            macro_vector.clearAndFree();

            // reset building mode
            building_mode = .UNDEFINED;

            // skip linefinish token
            continue;
        }

        // strip define tokens
        if (building_mode == .DEFINE)
            continue;

        try token_vector.append(try token.Copy(allocator));
    }

    if (macro_vector.items.len > 0) {
        std.log.err("Unflushed macro!", .{});
        return error.BadMacro;
    }

    return token_vector.toOwnedSlice();
}

/// unwraps the macros identifiers into a new token array
fn Second_Pass(allocator: std.mem.Allocator, symTable: *sym.SymbolTable, tokens: []const tok.Token) ![]tok.Token {
    var token_vector = std.ArrayList(tok.Token).init(allocator);
    defer token_vector.deinit();

    var last_macro_tokentype: tok.TokenType = .UNDEFINED;
    for (tokens) |token| {
        if (token.tokType == .IDENTIFIER) {
            const symbol = symTable.*.Get(token.identKey);
            // pay no mind to missing identifiers
            if (symbol == null) {
                try token_vector.append(try token.Copy(allocator));
                continue;
            }

            switch (symbol.?.value) {
                // append macro contents, one by one
                .macro => {
                    for (symbol.?.value.macro) |macroTok| {
                        try token_vector.append(try macroTok.Copy(allocator));
                        last_macro_tokentype = macroTok.tokType;
                    }
                    continue;
                },
                .define => {
                    try token_vector.append(try symbol.?.value.define.Copy(allocator));
                    continue;
                },
                else => {},
            }
        }
        // TODO: review this, from a glance this logic does not look bulletproof.
        // skip addition of unecessary newline token
        if (token.tokType == .LINEFINISH and last_macro_tokentype == .LINEFINISH)
            continue;

        last_macro_tokentype = .UNDEFINED;
        try token_vector.append(try token.Copy(allocator));
    }

    return token_vector.toOwnedSlice();
}
