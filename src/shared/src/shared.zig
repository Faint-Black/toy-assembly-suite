//=============================================================//
//                                                             //
//                    SHARED MODULE INDEX                      //
//                                                             //
//   Anchor source file for creation of the shared module.     //
//                                                             //
//=============================================================//

pub const utils = @import("utils.zig");
pub const streams = @import("streams.zig");
pub const specifications = @import("specifications.zig");
pub const machine = @import("machine.zig");
pub const warn = @import("warning.zig");

test {
    _ = @import("utils.zig");
    _ = @import("streams.zig");
    _ = @import("specifications.zig");
    _ = @import("machine.zig");
    _ = @import("warning.zig");
}
