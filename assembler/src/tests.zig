//=============================================================//
//                                                             //
//                            TESTS                            //
//                                                             //
//   Include all source files here to be tested during the     //
//  build phase.                                               //
//                                                             //
//=============================================================//

// hardcoded filepath in build.zig until the Zig engineers figure out how
// to recursively and automatically find and execute the tests in all the
// individual source files...
test {
    _ = @import("main.zig");
    _ = @import("utils.zig");
    _ = @import("tests.zig");
    _ = @import("codegen.zig");
    _ = @import("token.zig");
    _ = @import("symbol.zig");
    _ = @import("lexer.zig");
}
