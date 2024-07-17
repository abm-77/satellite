const std = @import("std");
const elf = @import("dbg/elf.zig");
const dwarf = @import("dbg/dwarf.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var info = try elf.ElfInfo.init(allocator, "scratch/test");
    defer info.deinit();

    try dwarf.init(allocator, info);
}
