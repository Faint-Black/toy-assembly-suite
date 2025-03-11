//=============================================================//
//                                                             //
//                    SHARED MODULE INDEX                      //
//                                                             //
//   Anchor source file for creation of the shared module.     //
//                                                             //
//=============================================================//

pub const utils = @import("utils.zig");
pub const specifications = @import("specifications.zig");

test {
    _ = @import("utils.zig");
    _ = @import("specifications.zig");
}
