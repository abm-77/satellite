const std = @import("std");
const dwarf = std.dwarf;

pub fn init(allocator: std.mem.Allocator) !void {
    var dwarf_info = std.mem.zeroes(dwarf.DwarfInfo);
    try dwarf.openDwarfDebugInfo(&dwarf_info, allocator);
}
