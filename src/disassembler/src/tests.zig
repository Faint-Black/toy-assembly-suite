//=============================================================//
//                                                             //
//                            TESTS                            //
//                                                             //
//   Include all source files here to be tested during the     //
//  build phase.                                               //
//                                                             //
//=============================================================//

test {
    _ = @import("main.zig");
    _ = @import("disassemble.zig");
}
