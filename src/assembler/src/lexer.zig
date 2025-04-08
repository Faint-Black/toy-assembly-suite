//=============================================================//
//                                                             //
//                           LEXER                             //
//                                                             //
//   Responsible for turning the raw input string into an      //
//  array of usable tokens.                                    //
//                                                             //
//=============================================================//

const std = @import("std");
const utils = @import("shared").utils;
const tok = @import("token.zig");

pub fn Lexer(allocator: std.mem.Allocator, input: []const u8) ![]tok.Token {
    var token_vector = std.ArrayList(tok.Token).init(allocator);
    defer token_vector.deinit();

    var string_buffer: [utils.buffsize.medium]u8 = undefined;
    var string_buffsize: usize = 0;

    // for string and char literals, examples:
    // LDA 'a'
    // .db "Hello world!"
    // double quotes automatically appends a null terminator,
    // single quotes does not
    var stringLiteralMode: bool = false;
    var charLiteralMode: bool = false;
    var escapeChar: bool = false;

    // anything between a semicolon and a newline is considered a comment
    // comments are completely ignored
    var comment_mode: bool = false;

    for (input) |c| {
        if (c == ';' and stringLiteralMode == false)
            comment_mode = true;
        if (c == '\n')
            comment_mode = false;
        if (comment_mode)
            continue;

        // here begins the string literal construction code
        //-------------------------------------------------
        if (c == '\\' and escapeChar == false) {
            escapeChar = true;
            continue;
        }
        // deactivate escapeChar mode at the end of each loop iteration.
        // this probably can be put as a normal statement at the top of
        // the loop, but i'm too scared of messing up this somewhat
        // delicate code...
        defer escapeChar = false;

        if (c == '\"' and escapeChar == false) {
            stringLiteralMode = !stringLiteralMode;
            charLiteralMode = false;
            // automatically append a null terminator at the end on double quote string literals
            if (stringLiteralMode == false)
                try token_vector.append(tok.Token{ .tokType = .LITERAL, .value = 0 });
            continue;
        }
        if (c == '\'' and escapeChar == false) {
            stringLiteralMode = !stringLiteralMode;
            charLiteralMode = true;
            continue;
        }
        if (stringLiteralMode == true) {
            if (escapeChar == true) {
                switch (c) {
                    '0' => try token_vector.append(tok.Token{ .tokType = .LITERAL, .value = 0 }),
                    'n' => try token_vector.append(tok.Token{ .tokType = .LITERAL, .value = '\n' }),
                    't' => try token_vector.append(tok.Token{ .tokType = .LITERAL, .value = '\t' }),
                    '\\' => try token_vector.append(tok.Token{ .tokType = .LITERAL, .value = '\\' }),
                    '\"' => try token_vector.append(tok.Token{ .tokType = .LITERAL, .value = '\"' }),
                    '\'' => try token_vector.append(tok.Token{ .tokType = .LITERAL, .value = '\'' }),
                    else => {},
                }
                continue;
            }
            try token_vector.append(tok.Token{ .tokType = .LITERAL, .value = c });
            continue;
        }
        //-----------------------------------------------
        // here ends the string literal construction code

        // add any non-whitespace character to the word buffer
        if (utils.Is_Char_Whitespace(c) == false)
            try utils.Append_Char_To_String(&string_buffer, &string_buffsize, c);

        // turn finished word string into primitive token
        if (utils.Is_Char_Whitespace(c) and (string_buffsize > 0)) {
            const word_token = try Word_To_Token(allocator, string_buffer[0..string_buffsize]);
            try token_vector.append(word_token);
            string_buffsize = 0;
        }

        if (c == '\n') {
            if (token_vector.items.len == 0)
                continue;

            // ignore duplicate newlines
            if (token_vector.getLast().tokType != .LINEFINISH) {
                try token_vector.append(tok.Token{ .tokType = tok.TokenType.LINEFINISH });
            } else {
                continue;
            }
        }
    }

    // manually append EOF token at the end
    try token_vector.append(tok.Token{ .tokType = .ENDOFFILE });
    try token_vector.append(tok.Token{ .tokType = tok.TokenType.LINEFINISH });

    return token_vector.toOwnedSlice();
}

//-------------------------------------------------------------//
// STATIC PRIVATE FUNCTIONS                                    //
//-------------------------------------------------------------//

fn Word_To_Token(allocator: std.mem.Allocator, str: []const u8) !tok.Token {
    const first_char: u8 = str[0];
    const last_char: u8 = str[str.len - 1];

    // literal/address token parsing
    const number_token = try Parse_Number_Word(str);
    if (number_token != null)
        return number_token.?;

    // an anonymous label is any label that starts with the "@" character
    // the string contents are ignored as they are meant to be only used in
    // a relative position context
    if (first_char == '@' and last_char == ':') {
        return tok.Token{
            .tokType = .ANON_LABEL,
            // reinforcing the fact that anonymous labels are ANONYMOUS!!
            .identKey = null,
        };
    }

    // a label is any word with a ":" as the last character
    if (last_char == ':') {
        return tok.Token{
            .tokType = .LABEL,
            // "minus one" to exclude the colon from the identifier string
            .identKey = try utils.Copy_Of_String(allocator, str[0 .. str.len - 1]),
        };
    }

    // relative label parsing
    const relative_label = try Parse_Relative_Label(str);
    if (relative_label != null)
        return relative_label.?;

    // if all keyword checks fail, consider token as an identifier
    if (std.mem.eql(u8, str, "ERROR")) {
        return tok.Token{ .tokType = .ERROR };
    } else if (std.mem.eql(u8, str, ".db")) {
        return tok.Token{ .tokType = .DB };
    } else if (std.mem.eql(u8, str, ".dw")) {
        return tok.Token{ .tokType = .DW };
    } else if (std.mem.eql(u8, str, ".dd")) {
        return tok.Token{ .tokType = .DD };
    } else if (std.mem.eql(u8, str, ".macro")) {
        return tok.Token{ .tokType = .MACRO };
    } else if (std.mem.eql(u8, str, ".endmacro")) {
        return tok.Token{ .tokType = .ENDMACRO };
    } else if (std.mem.eql(u8, str, ".repeat")) {
        return tok.Token{ .tokType = .REPEAT };
    } else if (std.mem.eql(u8, str, ".endrepeat")) {
        return tok.Token{ .tokType = .ENDREPEAT };
    } else if (std.mem.eql(u8, str, ".define")) {
        return tok.Token{ .tokType = .DEFINE };
    } else if (std.mem.eql(u8, str, "SYSCALL")) {
        return tok.Token{ .tokType = .SYSCALL };
    } else if (std.mem.eql(u8, str, "STRIDE")) {
        return tok.Token{ .tokType = .STRIDE };
    } else if (std.mem.eql(u8, str, "LDA")) {
        return tok.Token{ .tokType = .LDA };
    } else if (std.mem.eql(u8, str, "LDX")) {
        return tok.Token{ .tokType = .LDX };
    } else if (std.mem.eql(u8, str, "LDY")) {
        return tok.Token{ .tokType = .LDY };
    } else if (std.mem.eql(u8, str, "STA")) {
        return tok.Token{ .tokType = .STA };
    } else if (std.mem.eql(u8, str, "STX")) {
        return tok.Token{ .tokType = .STX };
    } else if (std.mem.eql(u8, str, "STY")) {
        return tok.Token{ .tokType = .STY };
    } else if (std.mem.eql(u8, str, "A")) {
        return tok.Token{ .tokType = .A };
    } else if (std.mem.eql(u8, str, "X")) {
        return tok.Token{ .tokType = .X };
    } else if (std.mem.eql(u8, str, "Y")) {
        return tok.Token{ .tokType = .Y };
    } else if (std.mem.eql(u8, str, "PC")) {
        return tok.Token{ .tokType = .PC };
    } else if (std.mem.eql(u8, str, "SC")) {
        return tok.Token{ .tokType = .SC };
    } else if (std.mem.eql(u8, str, "CLC")) {
        return tok.Token{ .tokType = .CLC };
    } else if (std.mem.eql(u8, str, "SEC")) {
        return tok.Token{ .tokType = .SEC };
    } else if (std.mem.eql(u8, str, "LDA")) {
        return tok.Token{ .tokType = .LDA };
    } else if (std.mem.eql(u8, str, "LDX")) {
        return tok.Token{ .tokType = .LDX };
    } else if (std.mem.eql(u8, str, "LDY")) {
        return tok.Token{ .tokType = .LDY };
    } else if (std.mem.eql(u8, str, "STA")) {
        return tok.Token{ .tokType = .STA };
    } else if (std.mem.eql(u8, str, "STX")) {
        return tok.Token{ .tokType = .STX };
    } else if (std.mem.eql(u8, str, "STY")) {
        return tok.Token{ .tokType = .STY };
    } else if (std.mem.eql(u8, str, "JMP")) {
        return tok.Token{ .tokType = .JMP };
    } else if (std.mem.eql(u8, str, "JSR")) {
        return tok.Token{ .tokType = .JSR };
    } else if (std.mem.eql(u8, str, "RET")) {
        return tok.Token{ .tokType = .RET };
    } else if (std.mem.eql(u8, str, "CMP")) {
        return tok.Token{ .tokType = .CMP };
    } else if (std.mem.eql(u8, str, "BCS")) {
        return tok.Token{ .tokType = .BCS };
    } else if (std.mem.eql(u8, str, "BCC")) {
        return tok.Token{ .tokType = .BCC };
    } else if (std.mem.eql(u8, str, "BEQ")) {
        return tok.Token{ .tokType = .BEQ };
    } else if (std.mem.eql(u8, str, "BNE")) {
        return tok.Token{ .tokType = .BNE };
    } else if (std.mem.eql(u8, str, "BMI")) {
        return tok.Token{ .tokType = .BMI };
    } else if (std.mem.eql(u8, str, "BPL")) {
        return tok.Token{ .tokType = .BPL };
    } else if (std.mem.eql(u8, str, "BVS")) {
        return tok.Token{ .tokType = .BVS };
    } else if (std.mem.eql(u8, str, "BVC")) {
        return tok.Token{ .tokType = .BVC };
    } else if (std.mem.eql(u8, str, "ADD")) {
        return tok.Token{ .tokType = .ADD };
    } else if (std.mem.eql(u8, str, "SUB")) {
        return tok.Token{ .tokType = .SUB };
    } else if (std.mem.eql(u8, str, "INC")) {
        return tok.Token{ .tokType = .INC };
    } else if (std.mem.eql(u8, str, "DEC")) {
        return tok.Token{ .tokType = .DEC };
    } else if (std.mem.eql(u8, str, "PUSH")) {
        return tok.Token{ .tokType = .PUSH };
    } else if (std.mem.eql(u8, str, "POP")) {
        return tok.Token{ .tokType = .POP };
    } else if (std.mem.eql(u8, str, "BRK")) {
        return tok.Token{ .tokType = .BRK };
    } else if (std.mem.eql(u8, str, "NOP")) {
        return tok.Token{ .tokType = .NOP };
    } else {
        // all keyword checks failed, return as identifier
        return tok.Token{
            .tokType = .IDENTIFIER,
            .identKey = try utils.Copy_Of_Slice(u8, allocator, str),
        };
    }
}

fn Parse_Number_Word(str: []const u8) !?tok.Token {
    var is_address = false;
    var base: u8 = 0;

    // to be a number token the following characters are accepted:
    // [0-9][a-f][A-F] to represent the numbers
    // "$" prefix to represent an address
    // "0x" to represent a hexadecimal base
    // "0d" to represent a decimal base
    for (str) |c| {
        if (!(utils.Is_Char_Hexadecimal_Digit(c)) and !(c == '$') and !(c == 'x') and !(c == 'd'))
            return null;
    }

    if (str[0] == '$')
        is_address = true;

    // positional interference based on existance of address prefix character
    // address: $0xff
    // literal: 0xff
    if (is_address) {
        if (str[1] == '0' and str[2] == 'x')
            base = 16;
        if (str[1] == '0' and str[2] == 'd')
            base = 10;
    } else {
        if (str[0] == '0' and str[1] == 'x')
            base = 16;
        if (str[0] == '0' and str[1] == 'd')
            base = 10;
    }

    // bases are mandatory in this language.
    // if no base is provided, exit the function
    if (base == 0)
        return null;

    // clean the string by removing the "0x" and "$"
    var buffer: [utils.buffsize.small]u8 = undefined;
    var buffsize: usize = 0;
    var passed_base = false;
    for (str) |c| {
        if (c == '$')
            continue;

        if (((c == 'x') or (c == 'd')) and (passed_base == false)) {
            passed_base = true;
            continue;
        }

        if (passed_base == false)
            continue;

        buffer[buffsize] = c;
        buffsize += 1;
    }

    // now to transform the string into a number
    const token_value = std.fmt.parseUnsigned(u32, buffer[0..buffsize], base) catch |err| {
        if (std.mem.eql(u8, @errorName(err), "Overflow")) {
            return error.NumTooLarge;
        } else {
            return error.Unknown;
        }
    };

    // and decide its type
    var token_type: tok.TokenType = undefined;
    if (is_address) {
        token_type = .ADDRESS;
    } else {
        token_type = .LITERAL;
    }

    // addresses cannot be larger than 0xFFFF (16-bit)
    if (token_type == .ADDRESS and token_value > 0xFFFF)
        return error.AddrTooLarge;

    return tok.Token{
        .value = token_value,
        .tokType = token_type,
    };
}

fn Parse_Relative_Label(str: []const u8) !?tok.Token {
    // examples:
    // @+
    // @--
    // there is no (practical) limit to the ammount of signs you can add.
    // as long as they are all minuses or pluses, no mixing.

    if (str.len < 2)
        return null;

    if (str[0] != '@')
        return null;

    const symbols_array = str[1..];
    // check if it qualifies as an relative label reference
    for (symbols_array) |operator_symbol| {
        if (operator_symbol != '+' and operator_symbol != '-')
            return null;
    }

    // plus or minus?
    const operator_character: u8 = symbols_array[0];
    // how many of them?
    const counter: u32 = @truncate(symbols_array.len);

    // check if all operators are uniform,
    // error example: @--+-
    for (symbols_array) |operator_symbol| {
        if (operator_symbol != operator_character)
            return error.MixedOperatorsInRelativeLabel;
    }

    const token_type: tok.TokenType = if (operator_character == '-') tok.TokenType.BACKWARD_LABEL_REF else tok.TokenType.FORWARD_LABEL_REF;
    return tok.Token{
        .tokType = token_type,
        .value = counter,
    };
}

//-------------------------------------------------------------//
// ONLY TESTS BELOW THIS POINT                                 //
//-------------------------------------------------------------//
test "value token parsing" {
    var error_token: anyerror!?tok.Token = undefined;
    var maybe_token: ?tok.Token = undefined;
    var value_token: tok.Token = undefined;

    // expects a valid result
    maybe_token = try Parse_Number_Word("0xFF");
    try std.testing.expect(maybe_token != null);
    value_token = maybe_token.?;
    try std.testing.expect(value_token.identKey == null);
    try std.testing.expect(value_token.text == null);
    try std.testing.expect(value_token.tokType == tok.TokenType.LITERAL);
    try std.testing.expectEqual(@as(u32, 255), value_token.value);

    // expects a valid result
    maybe_token = try Parse_Number_Word("0xFFFF");
    try std.testing.expect(maybe_token != null);
    value_token = maybe_token.?;
    try std.testing.expect(value_token.identKey == null);
    try std.testing.expect(value_token.text == null);
    try std.testing.expect(value_token.tokType == tok.TokenType.LITERAL);
    try std.testing.expectEqual(@as(u32, 65535), value_token.value);

    // expects a valid result
    maybe_token = try Parse_Number_Word("0d1337");
    try std.testing.expect(maybe_token != null);
    value_token = maybe_token.?;
    try std.testing.expect(value_token.identKey == null);
    try std.testing.expect(value_token.text == null);
    try std.testing.expect(value_token.tokType == tok.TokenType.LITERAL);
    try std.testing.expectEqual(@as(u32, 1337), value_token.value);

    // expects a valid result
    maybe_token = try Parse_Number_Word("$0xFFFF");
    try std.testing.expect(maybe_token != null);
    value_token = maybe_token.?;
    try std.testing.expect(value_token.identKey == null);
    try std.testing.expect(value_token.text == null);
    try std.testing.expect(value_token.tokType == tok.TokenType.ADDRESS);
    try std.testing.expectEqual(@as(u32, 65535), value_token.value);

    // expects a valid result
    maybe_token = try Parse_Number_Word("$0d1337");
    try std.testing.expect(maybe_token != null);
    value_token = maybe_token.?;
    try std.testing.expect(value_token.identKey == null);
    try std.testing.expect(value_token.text == null);
    try std.testing.expect(value_token.tokType == tok.TokenType.ADDRESS);
    try std.testing.expectEqual(@as(u32, 1337), value_token.value);

    // bogus input
    maybe_token = try Parse_Number_Word("Dojyaaan");
    try std.testing.expect(maybe_token == null);

    // no negative numbers allowed
    maybe_token = try Parse_Number_Word("0d-100");
    try std.testing.expect(maybe_token == null);

    // a complete base prefix must be provided
    maybe_token = try Parse_Number_Word("0FF");
    try std.testing.expect(maybe_token == null);
    maybe_token = try Parse_Number_Word("xFF");
    try std.testing.expect(maybe_token == null);
    maybe_token = try Parse_Number_Word("0XFF");
    try std.testing.expect(maybe_token == null);
    maybe_token = try Parse_Number_Word("100");
    try std.testing.expect(maybe_token == null);
    maybe_token = try Parse_Number_Word("$0FF");
    try std.testing.expect(maybe_token == null);
    maybe_token = try Parse_Number_Word("$xFF");
    try std.testing.expect(maybe_token == null);
    maybe_token = try Parse_Number_Word("$0XFF");
    try std.testing.expect(maybe_token == null);
    maybe_token = try Parse_Number_Word("$100");
    try std.testing.expect(maybe_token == null);

    // must be a valid, in range, 32-bit unsigned integer
    error_token = Parse_Number_Word("0xFFFFFFFF0");
    try std.testing.expectError(error.NumTooLarge, error_token);
    // addresses must be 16-bit
    error_token = Parse_Number_Word("$0xFFFF0");
    try std.testing.expectError(error.AddrTooLarge, error_token);
}

test "relative label reference parsing" {
    var error_token: anyerror!?tok.Token = undefined;
    var maybe_token: ?tok.Token = undefined;
    var value_token: tok.Token = undefined;

    // expects a valid result
    maybe_token = try Parse_Relative_Label("@-");
    try std.testing.expect(maybe_token != null);
    value_token = maybe_token.?;
    try std.testing.expect(value_token.tokType == .BACKWARD_LABEL_REF);
    try std.testing.expectEqual(@as(u32, 1), value_token.value);

    // expects a valid result
    maybe_token = try Parse_Relative_Label("@+++++++++++++++++++++++++++++++++++++++++++++");
    try std.testing.expect(maybe_token != null);
    value_token = maybe_token.?;
    try std.testing.expect(value_token.tokType == .FORWARD_LABEL_REF);
    try std.testing.expectEqual(@as(u32, 45), value_token.value);

    // bogus input
    maybe_token = try Parse_Relative_Label("@+++Masayoshi+");
    try std.testing.expect(maybe_token == null);
    maybe_token = try Parse_Relative_Label("@Takanaka:");
    try std.testing.expect(maybe_token == null);
    maybe_token = try Parse_Relative_Label("@Tokyo_Reggie");
    try std.testing.expect(maybe_token == null);

    // must have at least one symbol
    maybe_token = try Parse_Relative_Label("@");
    try std.testing.expect(maybe_token == null);

    // must not case mixed operator symbols
    error_token = Parse_Relative_Label("@-+");
    try std.testing.expectError(error.MixedOperatorsInRelativeLabel, error_token);
    error_token = Parse_Relative_Label("@+-");
    try std.testing.expectError(error.MixedOperatorsInRelativeLabel, error_token);
    error_token = Parse_Relative_Label("@+++++-");
    try std.testing.expectError(error.MixedOperatorsInRelativeLabel, error_token);
    error_token = Parse_Relative_Label("@++-++++");
    try std.testing.expectError(error.MixedOperatorsInRelativeLabel, error_token);
}
