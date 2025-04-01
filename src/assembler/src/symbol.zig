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
    /// MACROS: expandes into multiple tokens during the preprocessor phase
    macro: []tok.Token,
    /// DEFINES: expands into a single token during the preprocessor phase
    define: tok.Token,

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
            // free the stack variable token contents
            .define => {
                self.define.Deinit(allocator);
            },
        }
    }
};

/// wrapper for an easier to use ArrayHashMap interface
pub const SymbolTable = struct {
    /// do not use this member directly!
    /// only use API functions
    table: std.StringArrayHashMap(Symbol),
    /// keep track of anonymous labels created so they can be named accordingly
    anonlabel_count: u32 = 0,

    pub fn Init(allocator: std.mem.Allocator) SymbolTable {
        return SymbolTable{ .table = std.StringArrayHashMap(Symbol).init(allocator) };
    }

    pub fn Deinit(this: *SymbolTable) void {
        const allocator = this.table.allocator;
        for (this.table.keys()) |k| {
            const sym = this.table.get(k).?;
            sym.Deinit(allocator);
        }
        this.table.deinit();
    }

    /// returns null on fail
    pub fn Get(self: SymbolTable, key: ?[]const u8) ?Symbol {
        if (key) |k|
            return self.table.get(k);
        return null;
    }

    /// replaces entry if it already exists
    pub fn Add(this: *SymbolTable, sym: Symbol) !void {
        const allocator = this.table.allocator;
        if (sym.name) |k| {
            // if entry already exists, deallocate original name and
            // replace contents with new entry
            if (this.table.getEntry(k)) |clash_entry| {
                // a lot of blood, sweat and tears went into these 2 lines of code
                // DO NOT TOUCH!!
                allocator.free(sym.name.?);
                clash_entry.value_ptr.value = sym.value;
                return;
            } else {
                try this.table.putNoClobber(k, sym);
                return;
            }
        }
        return error.NoIdentKey;
    }

    /// hacky solution, may need a rework in the future
    /// fetches the desired label token of a relative label reference
    pub fn Search_Relative_Label(self: SymbolTable, relTok: tok.Token, romPos: u32) !tok.Token {
        const allocator = self.table.allocator;

        var label_vector = std.ArrayList(tok.Token).init(allocator);
        defer label_vector.deinit();

        // add all symbol table LABEL symbols to the total vector
        for (self.table.keys()) |k| {
            if (self.Get(k)) |entry| {
                if (entry.value == .label) {
                    try label_vector.append(entry.value.label);
                }
            }
        }

        // we wont be needing the vector capabilities anymore
        const label_slice = try label_vector.toOwnedSlice();
        defer allocator.free(label_slice);

        if (label_slice.len == 0)
            return error.ZeroLabels;

        // i reeeeeally am not a fan of this syntax, but my hands are tied :/
        std.mem.sort(tok.Token, label_slice, {}, Ascending_Label_Sort(tok.Token));

        // "@+++" -> counter = 3, sign = '+'
        // "@--" -> counter = 2, sign = '-'
        // zig makes it an absolute hassle to deal with bitcasts,
        // so this is a way easier approach
        var counter_value: usize = relTok.value;
        const counter_sign: u8 = if (relTok.tokType == .BACKWARD_LABEL_REF) '-' else '+';

        // get the sorted list index of the previous, or equal, label address
        var previous_label_index: usize = 0;
        for (label_slice, 0..) |label_token, i| {
            if (label_token.value <= romPos) {
                previous_label_index = i;
            } else {
                break;
            }
        }

        var index: usize = undefined;
        if (counter_sign == '-') {
            // 1 is added due to the index being based on the position of the previous label
            counter_value = std.math.sub(usize, counter_value, 1) catch {
                return error.RelativeLabelOutOfBounds;
            };
            index = std.math.sub(usize, previous_label_index, counter_value) catch {
                return error.RelativeLabelOutOfBounds;
            };
        } else {
            index = std.math.add(usize, previous_label_index, counter_value) catch {
                return error.RelativeLabelOutOfBounds;
            };
        }

        return label_slice[index];
    }

    // sorting predicate function
    fn Ascending_Label_Sort(comptime T: type) fn (void, T, T) bool {
        return struct {
            fn inner(_: void, a: T, b: T) bool {
                return a.value < b.value;
            }
        }.inner;
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
                .define => {
                    std.debug.print("type: DEFINE\n", .{});
                    std.debug.print("expands to: {{ ", .{});
                    sym.value.define.Print();
                    std.debug.print(" }}\n", .{});
                },
            }
        }
    }
};
