//=============================================================//
//                                                             //
//                            TESTS                            //
//                                                             //
//   Include all source files here to be tested during the     //
//  build phase.                                               //
//                                                             //
//=============================================================//

test {
    _ = @import("shared");
    _ = @import("main.zig");
    _ = @import("tests.zig");
    _ = @import("codegen.zig");
    _ = @import("token.zig");
    _ = @import("symbol.zig");
    _ = @import("lexer.zig");
}
