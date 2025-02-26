//=============================================================//
//                                                             //
//                  SYMBOLS AND SYMBOL TABLE                   //
//                                                             //
//   Defines the symbols union as well as the symboltable      //
//  string hashmap wrapper.                                    //
//                                                             //
//=============================================================//

const std = @import("std");
const tok = @import("token.zig");

pub const Symbol = struct {
    /// string key that represents such symbol
    name: ?[]u8 = null,
    /// union symbol to be returned
    value: SymbolUnion = undefined,

    pub fn Deinit(self: Symbol, allocator: std.mem.Allocator) void {
        self.value.Deinit(allocator);
        if (self.name) |name|
            allocator.free(name);
    }
};

pub const SymbolUnion = union(enum) {
    /// LABELS: coerced into an address literal *during* codegen
    label: tok.Token,
    /// MACROS: expanded into its contents during the preprocessor phase
    macro: []tok.Token,

    /// different deallocation rules depending on union type
    pub fn Deinit(self: SymbolUnion, allocator: std.mem.Allocator) void {
        switch (self) {
            // free the stack variable token contents
            .label => {
                self.label.Deinit(allocator);
            },
            // free the pointer contents, then free the pointer itself
            .macro => {
                for (self.macro) |token|
                    token.Deinit(allocator);
                allocator.free(self.macro);
            },
        }
    }
};

/// wrapper for an easier to use ArrayHashMap interface
pub const SymbolTable = struct {
    /// do not use this member directly!
    /// only use API functions
    table: std.StringArrayHashMap(Symbol),

    pub fn Init(allocator: std.mem.Allocator) SymbolTable {
        return SymbolTable{ .table = std.StringArrayHashMap(Symbol).init(allocator) };
    }

    pub fn Deinit(this: *SymbolTable) void {
        const allocator = this.*.table.allocator;
        for (this.*.table.keys()) |k| {
            const sym = this.*.table.get(k).?;
            sym.Deinit(allocator);
        }
        this.*.table.deinit();
    }

    /// returns null on fail
    pub fn Get(self: SymbolTable, key: ?[]const u8) ?Symbol {
        if (key) |k|
            return self.table.get(k);
        return null;
    }

    /// replaces entry if it already exists
    pub fn Add(this: *SymbolTable, sym: Symbol) !void {
        const allocator = this.*.table.allocator;
        if (sym.name) |k| {
            // if entry already exists, deallocate original name and
            // replace contents with new entry
            if (this.*.table.getEntry(k)) |clash_entry| {
                // a lot of blood, sweat and tears went into these 2 lines of code
                // DO NOT TOUCH!!
                allocator.free(sym.name.?);
                clash_entry.value_ptr.*.value = sym.value;
                return;
            } else {
                try this.*.table.putNoClobber(k, sym);
                return;
            }
        }
        return error.NoIdentKey;
    }

    /// for debugging purposes
    pub fn Print(self: SymbolTable) void {
        const iterator = self.table.iterator();
        var i: usize = 0;
        while (i < iterator.len) : (i += 1) {
            const key = iterator.keys[i];
            const sym = self.table.get(key).?;

            std.debug.print("\nsymbol #{}:\n", .{i});
            std.debug.print("name: \"{?s}\"\n", .{sym.name});
            switch (sym.value) {
                .label => {
                    std.debug.print("type: LABEL\n", .{});
                    std.debug.print("address value: 0x{X}\n", .{sym.value.label.value});
                },
                .macro => {
                    std.debug.print("type: MACRO\n", .{});
                    std.debug.print("expands to:\n", .{});
                    tok.Print_Token_Array(sym.value.macro);
                },
            }
        }
    }
};
