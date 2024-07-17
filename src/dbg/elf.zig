const std = @import("std");
const print = std.debug.print;
const fs = std.fs;
const elf = std.elf;
const dwarf = std.dwarf;

const Buffer = []const u8;
const ElfSectionHeaderList = []elf.Elf64_Shdr;
const ElfProgramHeaderList = []elf.Elf64_Phdr;

const ElfError = error{
    CouldNotFindTableIndices,
};

const Validator = struct {
    pub fn nameEql(desired_name: []const u8, name_from_file: []u8) bool {
        const n = name_from_file[0..desired_name.len];
        return std.mem.eql(u8, desired_name, n);
    }

    pub fn isSymbolTable(shdr: elf.Elf64_Shdr, name: []u8) bool {
        return nameEql(".symtab", name) and
            shdr.sh_type == elf.SHT_SYMTAB and
            shdr.sh_flags & elf.SHF_ALLOC == 0 and
            shdr.sh_entsize == @sizeOf(elf.Elf64_Sym);
    }

    pub fn isStringTable(shdr: elf.Elf64_Shdr, name: []u8) bool {
        return nameEql(".strtab", name) and
            shdr.sh_type == elf.SHT_STRTAB and
            shdr.sh_flags & elf.SHF_ALLOC == 0;
    }
};

pub fn sliceAtOffset(comptime T: type, buffer: []const u8, offset: u64, count: u64) []T {
    const ptr = @intFromPtr(buffer.ptr) + offset;
    return @as([*]T, @ptrFromInt(ptr))[0..count];
}

const ElfProgramTable = struct {
    headers: ElfProgramHeaderList,
};

const ElfTableIndices = struct {
    symbol_table_index: u32,
    string_table_index: u32,
    section_name_string_table_index: u32,

    // Find the index of the symbol and string table headers
    pub fn init(
        n_headers: u64,
        section_headers: []elf.Elf64_Shdr,
        section_name_string_table: []u8,
        section_name_string_table_index: u32,
    ) !ElfTableIndices {
        var i: u32 = 0;
        var symbol_table_index: u32 = 0;
        var string_table_index: u32 = 0;
        while (i < n_headers and (symbol_table_index == 0 or string_table_index == 0)) : (i += 1) {
            const hdr = section_headers[i];
            const name = section_name_string_table[hdr.sh_name..];
            if (Validator.isSymbolTable(hdr, name)) symbol_table_index = i;
            if (Validator.isStringTable(hdr, name)) string_table_index = i;
        }

        if (symbol_table_index == 0 or string_table_index == 0) return error.CouldNotFindTableIndices;

        return .{
            .symbol_table_index = symbol_table_index,
            .string_table_index = string_table_index,
            .section_name_string_table_index = section_name_string_table_index,
        };
    }
};

const ElfSectionTable = struct {
    headers: ElfSectionHeaderList,
    table_indices: ElfTableIndices,
    symbol_table: []elf.Elf64_Sym,
    string_table: []u8,
    section_name_string_table: []u8,
};

pub const ElfInfo = struct {
    const Self = @This();

    elf_header: elf.Header,
    program_table: ElfProgramTable,
    section_table: ElfSectionTable,
    data: Buffer,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !ElfInfo {
        const fd = try fs.cwd().openFile(path, .{});
        defer fd.close();

        const stat = try fd.stat();
        var bytes = try allocator.alloc(u8, stat.size);
        _ = try fd.readAll(bytes);

        const elf_header = try elf.Header.read(fd);

        // Program Table
        var program_headers = sliceAtOffset(elf.Elf64_Phdr, bytes, elf_header.phoff, elf_header.phnum);
        const program_table = ElfProgramTable{
            .headers = program_headers,
        };

        // Section Table
        var section_headers = sliceAtOffset(elf.Elf64_Shdr, bytes, elf_header.shoff, elf_header.shnum);
        const initial_section_header = section_headers[0];
        if (elf_header.phnum == 0xffff) program_headers.len = initial_section_header.sh_info;
        if (elf_header.shnum == 0xffff) section_headers.len = initial_section_header.sh_size;
        const section_name_string_table_index = if (elf_header.shstrndx == 0xffff) initial_section_header.sh_link else elf_header.shstrndx;

        const section_name_string_table_header = section_headers[section_name_string_table_index];
        const section_name_string_table = bytes[section_name_string_table_header.sh_offset..];
        const table_indices = try ElfTableIndices.init(elf_header.shnum, section_headers, section_name_string_table, section_name_string_table_index);

        const symbol_table_header = section_headers[table_indices.symbol_table_index];
        const n_symbols = @divExact(symbol_table_header.sh_size, symbol_table_header.sh_entsize);
        const symbol_table = sliceAtOffset(elf.Elf64_Sym, bytes, symbol_table_header.sh_offset, n_symbols);

        const string_table_header = section_headers[table_indices.string_table_index];
        const string_table = bytes[string_table_header.sh_offset..];

        const section_table = ElfSectionTable{
            .headers = section_headers,
            .table_indices = table_indices,
            .symbol_table = symbol_table,
            .string_table = string_table,
            .section_name_string_table = section_name_string_table,
        };

        return ElfInfo{
            .elf_header = elf_header,
            .data = bytes,
            .program_table = program_table,
            .section_table = section_table,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.data);
    }

    fn symbolName(self: *Self, symbol: elf.Elf64_Sym) []const u8 {
        const string_table_header = self.section_table.headers[self.section_table.indices.string_table_index];
        const string_table = self.data[string_table_header.sh_offset..];
        return string_table[symbol.st_name];
    }

    pub fn getSymbolFromName(self: Self, name: []const u8) ?elf.Elf64_Sym {
        for (self.section_table.symbol_table) |symbol| {
            if (Validator.nameEql(name, self.symbolName(symbol))) return symbol;
        }
        return null;
    }

    pub fn getSymbolFromAddr(self: Self, addr: elf.Elf64_Addr) ?elf.Elf64_Sym {
        for (self.section_table.symbol_table) |symbol| {
            const start_addr = symbol.sh_value;
            const end_addr = symbol.sh_value + symbol.sh_size;
            if (addr >= start_addr and addr <= end_addr) return symbol;
        }
        return null;
    }

    pub fn findDwarfSection(self: Self, section_name: []const u8) ?dwarf.DwarfInfo.Section {
        const section_name_string_table = self.section_table.section_name_string_table;

        var found_section_header: ?elf.Elf64_Shdr = null;
        for (self.section_table.headers) |section_header| {
            if (section_header.sh_type != elf.SHT_PROGBITS) continue;
            const curr_name = section_name_string_table[section_header.sh_name..];
            const found = Validator.nameEql(section_name, curr_name);
            if (found) {
                found_section_header = section_header;
                break;
            }
        }

        if (found_section_header) |section_header| {
            print("found {s}: {any}\n\n", .{ section_name, section_header });
            const size = section_header.sh_size;
            const offset = section_header.sh_offset;
            const section_data = self.data[offset .. offset + size];

            return dwarf.DwarfInfo.Section{
                .data = section_data,
                .owned = false,
                .virtual_address = null,
            };
        } else {
            print("did not find {s}\n\n", .{section_name});
        }
        return null;
    }
};
