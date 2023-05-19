const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

/// Only for c interop. Caller owns the memory.
pub fn makeNullTerminatedString(allocator: Allocator, str: []const u8) ![]u8 {
    var c_str = try allocator.alloc(u8, str.len + 1);
    @memcpy(c_str[0..str.len], str);
    c_str[str.len] = 0;
    return c_str;
}

/// This is pretty useless TBH, didn't realize format "{any}" works.
pub fn printArrayListToBuff(comptime T: type, list: ArrayList(T), comptime elemFmt: []const u8, buff: []u8) ![]u8 {
    var written: []u8 = undefined;
    written = try std.fmt.bufPrint(buff, "[", .{});
    var n: usize = 1;
    for (list.items, 0..) |item, i| {
        written = try std.fmt.bufPrint(buff[n..], elemFmt, .{item});
        n += written.len;
        if (i < list.items.len - 1) {
            written = try std.fmt.bufPrint(buff[n..], ",", .{});
            n += written.len;
        }
    }
    written = try std.fmt.bufPrint(buff[n..], "]", .{});
    n += 1;
    return buff[0..n];
}
