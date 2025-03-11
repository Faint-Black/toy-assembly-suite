//=============================================================//
//                                                             //
//                    SHARED MODULE INDEX                      //
//                                                             //
//   Anchor source file for creation of the shared module.     //
//                                                             //
//=============================================================//

pub const utils = @import("utils.zig");

test {
    _ = @import("utils.zig");
}
