const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

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

pub fn bufPrintNull(buff: []u8, comptime fmt: []const u8, args: anytype) ![]u8 {
    var written: []u8 = undefined;
    written = try std.fmt.bufPrint(buff, fmt, args);
    buff[written.len] = 0;
    return buff[0..written.len];
}

/// fields_to_ignore needs to be a comptime constant array of []const u8
pub fn debugPrintObjectIgnoringFields(comptime T: type, obj: *T, comptime fields_to_ignore: anytype) void {
    std.debug.print("[{s}]\n", .{@typeName(T)});
    var ignore_nxt = false;
    inline for (@typeInfo(T).Struct.fields) |fld| {
        ignore_nxt = false;
        inline for (fields_to_ignore) |ignore_fld_name| {
            if (std.mem.eql(u8, fld.name, ignore_fld_name)) {
                ignore_nxt = true;
            }
        }
        if (!ignore_nxt) std.debug.print(" -{s}: {any}\n", .{ fld.name, @field(obj, fld.name) });
    }
}

pub fn debugPrintObject(comptime T: type, obj: *T) void {
    std.debug.print("[{s}]\n", .{@typeName(T)});
    inline for (@typeInfo(T).Struct.fields) |fld| {
        std.debug.print(" -{s}: {any}\n", .{ fld.name, @field(obj, fld.name) });
    }
}
