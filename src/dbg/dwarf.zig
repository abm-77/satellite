const std = @import("std");
const zelf = @import("elf.zig");
const elf = std.elf;
const dwarf = std.dwarf;
const print = std.debug.print;

const Section = dwarf.DwarfInfo.Section;
const SectionArray = dwarf.DwarfInfo.SectionArray;
const FuncAddrMap = std.StringHashMap(u64);

pub fn init(allocator: std.mem.Allocator, ei: zelf.ElfInfo) !void {
    const section_array = std.enums.directEnumArray(
        dwarf.DwarfSection,
        ?Section,
        14,
        .{
            .debug_info = ei.findDwarfSection(".debug_info"),
            .debug_abbrev = ei.findDwarfSection(".debug_abbrev"),
            .debug_str = ei.findDwarfSection(".debug_str"),
            .debug_str_offsets = ei.findDwarfSection(".debug_str_o"),
            .debug_line = ei.findDwarfSection(".debug_line"),
            .debug_line_str = ei.findDwarfSection(".debug_line_str"),
            .debug_addr = ei.findDwarfSection(".debug_addr"),
            .debug_names = ei.findDwarfSection(".debug_names"),
            .debug_frame = ei.findDwarfSection(".debug_frame"),
            .debug_rnglists = ei.findDwarfSection(".debug_rnglists"),
            .debug_ranges = ei.findDwarfSection(".debug_ranges"),
            .debug_loclists = ei.findDwarfSection(".debug_loclists"),
            .eh_frame = ei.findDwarfSection(".eh_frame"),
            .eh_frame_hdr = ei.findDwarfSection(".eh_frame_hdr"),
        },
    );

    var dwarf_info = dwarf.DwarfInfo{
        .endian = ei.elf_header.endian,
        .is_macho = false,
        .sections = section_array,
    };

    try dwarf.openDwarfDebugInfo(&dwarf_info, allocator);
    defer dwarf_info.deinit(allocator);

    var func_name_to_addr = FuncAddrMap.init(allocator);
    defer func_name_to_addr.deinit();

    for (dwarf_info.func_list.items) |func| {
        if (func.name) |name| {
            print("function: {s}", .{name});
            if (func.pc_range) |range| {
                print(", start: 0x{x}, end: 0x{x}", .{ range.start, range.end });
                try func_name_to_addr.put(name, range.start);
            }
            print("\n", .{});
        }
    }

    const loop_cu = try dwarf_info.findCompileUnit(func_name_to_addr.get("loop").?);
    const loop_die = loop_cu.die;
    for (loop_die.attrs) |attr| {
        print("attr:\n\tid = 0x{x},\n\tvalue = {any}\n", .{ attr.id, attr.value });
    }
    //print("{s}\n", .{loop_die.attrs[0x3].value.strx});
}
