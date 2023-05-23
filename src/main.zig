const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const raylib = @cImport(@cInclude("raylib.h"));
pub const rlgl = @cImport(@cInclude("rlgl.h"));

pub const math = @import("math/math.zig");
const Vec2 = math.Vec2;
const Rect = math.geo.Rect;
const Mat3 = math.Mat3;

pub const geo = @import("math/geo/geo.zig");
pub const gfx = @import("gfx.zig");
pub const cam = @import("cam.zig");
pub const util = @import("util.zig");

pub const ObjectStore = @import("object_store.zig").ObjectStore;

const bunnyTest = @import("bunny_test.zig").bunnyTest;
const circuitTest = @import("circuits/circuit_simulator.zig").circuitTest;
const initiateCircuitSandbox = @import("circuits/logiverse.zig").initiateCircuitSandbox;

pub const std_options = struct {
    pub const logFn = customLogFn;
};

/// modified from std lib example: https://ziglang.org/documentation/master/std/#A;std:log
fn customLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;
    const prefix = "[" ++ comptime level.asText() ++ "] ";
    // Print the message to stderr, silently ignoring any errors
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}

pub fn main() !void {
    std.debug.print("It's a busy day ahead!\n", .{});
    try initiateCircuitSandbox();
    // try circuitTest();
    // try bunnyTest();
    // try geo.doRadiusQueryBenchmark();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "matrix det" {
    const MatT = Mat3(f32);
    const ColVec = MatT.ColumnVec;
    const eps = 0.0001;
    var m = Mat3(f32).fromColumns(
        ColVec{ 4, 2, -3 },
        ColVec{ 1, -1, 2 },
        ColVec{ 5, 3, 0 },
    );
    var det = m.det();
    try std.testing.expectApproxEqRel(det, -28, eps);
    m = Mat3(f32).fromColumns(
        ColVec{ 2, 4, 1 },
        ColVec{ 6, -1, 3 },
        ColVec{ 3, 3, 2 },
    );
    det = m.det();
    try std.testing.expectApproxEqRel(det, -13, eps);
}

test "matrix inv test" {
    const eps: f32 = 0.0001;
    const MatT = Mat3(f32);
    const ColVec = MatT.ColumnVec;
    var m = Mat3(f32).fromColumns(
        ColVec{ 1, 4, 0 },
        ColVec{ 0, 2, 3 },
        ColVec{ -3, -1, 2 },
    );
    var maybe_inv = m.inverse();
    try std.testing.expect(maybe_inv != null);
    var inv = maybe_inv orelse unreachable;
    try std.testing.expectApproxEqRel(@as(f32, -7.0 / 29.0), inv.c[0][0], eps);
    try std.testing.expectApproxEqRel(@as(f32, 8.0 / 29.0), inv.c[0][1], eps);
    try std.testing.expectApproxEqRel(@as(f32, -12.0 / 29.0), inv.c[0][2], eps);
    try std.testing.expectApproxEqRel(@as(f32, 9.0 / 29.0), inv.c[1][0], eps);
    try std.testing.expectApproxEqRel(@as(f32, -2.0 / 29.0), inv.c[1][1], eps);
    try std.testing.expectApproxEqRel(@as(f32, 3.0 / 29.0), inv.c[1][2], eps);
    try std.testing.expectApproxEqRel(@as(f32, -6.0 / 29.0), inv.c[2][0], eps);
    try std.testing.expectApproxEqRel(@as(f32, 11.0 / 29.0), inv.c[2][1], eps);
    try std.testing.expectApproxEqRel(@as(f32, -2.0 / 29.0), inv.c[2][2], eps);
}

test "matrix inv test2" {
    const eps: f32 = 0.0001;
    const MatT = Mat3(f32);
    const ColVec = MatT.ColumnVec;
    const m = Mat3(f32).fromColumns(
        ColVec{ 3, 2, 0 },
        ColVec{ 0, 0, 1 },
        ColVec{ 2, -2, 1 },
    );

    const mm = m.getMinorMatrix();
    // mm.debugPrint();
    try std.testing.expectApproxEqRel(@as(f32, 2), mm.c[0][0], eps);
    try std.testing.expectApproxEqRel(@as(f32, -2), mm.c[0][1], eps);
    try std.testing.expectApproxEqRel(@as(f32, 0), mm.c[0][2], eps);

    try std.testing.expectApproxEqRel(@as(f32, 2), mm.c[1][0], eps);
    try std.testing.expectApproxEqRel(@as(f32, 3), mm.c[1][1], eps);
    try std.testing.expectApproxEqRel(@as(f32, -10), mm.c[1][2], eps);

    try std.testing.expectApproxEqRel(@as(f32, 2), mm.c[2][0], eps);
    try std.testing.expectApproxEqRel(@as(f32, 3), mm.c[2][1], eps);
    try std.testing.expectApproxEqRel(@as(f32, 0), mm.c[2][2], eps);
}

test "matrix inv test3" {
    const eps: f32 = 0.0001;
    const MatT = Mat3(f32);
    const ColVec = MatT.ColumnVec;
    const m = Mat3(f32).fromColumns(
        ColVec{ 4, 1, 5 },
        ColVec{ 2, -1, 3 },
        ColVec{ -3, 2, 0 },
    );

    const det = m.det();
    try std.testing.expectApproxEqRel(@as(f32, -28), det, eps);

    const adj = m.getAdjugate();
    // adj.debugPrint();
    try std.testing.expectApproxEqRel(@as(f32, -6), adj.c[0][0], eps);
    try std.testing.expectApproxEqRel(@as(f32, 10), adj.c[0][1], eps);
    try std.testing.expectApproxEqRel(@as(f32, 8), adj.c[0][2], eps);
    try std.testing.expectApproxEqRel(@as(f32, -9), adj.c[1][0], eps);
    try std.testing.expectApproxEqRel(@as(f32, 15), adj.c[1][1], eps);
    try std.testing.expectApproxEqRel(@as(f32, -2), adj.c[1][2], eps);
    try std.testing.expectApproxEqRel(@as(f32, 1), adj.c[2][0], eps);
    try std.testing.expectApproxEqRel(@as(f32, -11), adj.c[2][1], eps);
    try std.testing.expectApproxEqRel(@as(f32, -6), adj.c[2][2], eps);

    var maybe_inv = m.inverse();
    try std.testing.expect(maybe_inv != null);
    var inv = maybe_inv orelse unreachable;
    // inv.debugPrint();
    try std.testing.expectApproxEqRel(@as(f32, 3.0 / 14.0), inv.c[0][0], eps);
    try std.testing.expectApproxEqRel(@as(f32, -5.0 / 14.0), inv.c[0][1], eps);
    try std.testing.expectApproxEqRel(@as(f32, -2.0 / 7.0), inv.c[0][2], eps);
    try std.testing.expectApproxEqRel(@as(f32, 9.0 / 28.0), inv.c[1][0], eps);
    try std.testing.expectApproxEqRel(@as(f32, -15.0 / 28.0), inv.c[1][1], eps);
    try std.testing.expectApproxEqRel(@as(f32, 1.0 / 14.0), inv.c[1][2], eps);
    try std.testing.expectApproxEqRel(@as(f32, -1.0 / 28.0), inv.c[2][0], eps);
    try std.testing.expectApproxEqRel(@as(f32, 11.0 / 28.0), inv.c[2][1], eps);
    try std.testing.expectApproxEqRel(@as(f32, 3.0 / 14.0), inv.c[2][2], eps);
}

test "hashmap test" {
    var allocator = std.heap.page_allocator;
    var hash = std.AutoArrayHashMap(usize, f32).init(allocator);
    var key: usize = 123;
    var value: f32 = 99.0;
    try hash.put(key, value);
    var maybe_value = hash.get(key);
    try std.testing.expect(maybe_value != null);
    var value2 = maybe_value orelse unreachable;
    try std.testing.expectEqual(value, value2);
}

test "rect bounds test" {
    const rect = Rect(f32).init(Vec2(f32).zero, Vec2(f32).fill(1000));
    try std.testing.expect(!rect.containsPoint(Vec2(f32).init(-0.00000000000030316488252093987, -0.00000000000030316488252093987)));
    try std.testing.expect(rect.containsPoint(Vec2(f32).init(778.1972045898438, 778.1972045898438)));
    try std.testing.expect(!rect.containsPoint(Vec2(f32).init(1000, 1000)));
    try std.testing.expect(!rect.containsPoint(Vec2(f32).init(1001, 1001)));
    try std.testing.expect(!rect.containsPoint(Vec2(f32).init(-1, -1)));
}

test "print ArrayList" {
    const allocator = std.heap.page_allocator;
    var list = ArrayList(usize).init(allocator);
    for (0..10) |i| {
        try list.append(i);
    }
    var buff: [1024]u8 = undefined;
    const formatted_slice = try util.printArrayListToBuff(usize, list, "{d}", &buff);
    const expected = "[0,1,2,3,4,5,6,7,8,9]";
    try std.testing.expectEqualSlices(u8, expected, formatted_slice);
}

test "print ArrayList wait does this work?" {
    const allocator = std.heap.page_allocator;
    var list = ArrayList(usize).init(allocator);
    for (0..10) |i| {
        try list.append(i);
    }
    var buff: [100]u8 = undefined;
    const formatted_slice = try std.fmt.bufPrint(&buff, "{any}", .{list.items});
    try std.testing.expectEqualSlices(u8, "{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }", formatted_slice);
}

test "ObjectStore works" {
    const allocator = std.heap.page_allocator;
    var objs = ObjectStore(usize).init(allocator);
    for (0..5) |i| {
        _ = try objs.store(i);
    }

    var cursedIndex: usize = 3;
    try std.testing.expectEqual(cursedIndex, objs.get(cursedIndex));
    try objs.remove(cursedIndex);

    // this will give unreachable error:
    // _ = objs.get(5);

    var bob: usize = 99;
    var bobId = try objs.store(bob);

    // previously removed index should have been recycled:
    try std.testing.expectEqual(cursedIndex, bobId);
    try std.testing.expectEqual(bob, objs.get(cursedIndex));

    var iter = objs.iterator();
    var obj0 = iter.next();
    try std.testing.expectEqual(@as(usize, 0), obj0.?.*);
    var obj1 = iter.next();
    try std.testing.expectEqual(@as(usize, 1), obj1.?.*);
    var obj2 = iter.next();
    try std.testing.expectEqual(@as(usize, 2), obj2.?.*);
    var obj3 = iter.next();
    try std.testing.expectEqual(@as(usize, bob), obj3.?.*);
    var obj4 = iter.next();
    try std.testing.expectEqual(@as(usize, 4), obj4.?.*);
    var obj5 = iter.next();
    try std.testing.expectEqual(@as(?*usize, null), obj5);
}

test "test enum to int" {
    const Foods = enum {
        apple,
        banana,
        orange,
    };
    var map = std.AutoHashMap(Foods, usize).init(std.heap.page_allocator);
    try map.put(.apple, 1);
    var e0 = map.get(.apple);
    try std.testing.expectEqual(e0, @as(?usize, 1));
    try std.testing.expectEqual(@as(usize, 1), @enumToInt(Foods.banana));
}

test "test union of structs" {
    const Cow = packed struct {
        id: usize,
        age: u32,
        grass_chew_rate: f32,

        const Self = @This();
        pub fn complain(self: *Self) void {
            _ = self;
            std.debug.print("Mooooo!\n", .{});
        }
    };
    const Karen = packed struct {
        id: usize,
        complaint_count: u32,
        anger_level: f32,

        const Self = @This();
        pub fn complain(self: *Self) void {
            self.complaint_count += 1;
            self.anger_level -= 0.25;
        }
    };
    const CowOrKaren = extern union {
        cow: Cow,
        karen: Karen,
    };
    var obj0: CowOrKaren = .{ .cow = .{ .id = 69, .age = 420, .grass_chew_rate = 1 } };
    var obj1: CowOrKaren = .{ .karen = .{ .id = 1, .complaint_count = 9900, .anger_level = 9134.25 } };

    var cow_ptr = &obj0.cow;
    try std.testing.expectEqual(@as(usize, 69), cow_ptr.id);

    var karen_ptr = @ptrCast(*Karen, cow_ptr);
    karen_ptr.id = 99;
    karen_ptr.complain();
    try std.testing.expectEqual(@as(usize, 99), cow_ptr.id);
    try std.testing.expectEqual(@as(usize, 421), cow_ptr.age);
    try std.testing.expectEqual(@as(f32, 0.75), cow_ptr.grass_chew_rate);

    var karen = &obj1.karen;
    try std.testing.expectEqual(@as(u32, 9900), karen.complaint_count);
    karen.complain();
    try std.testing.expectEqual(@as(u32, 9901), karen.complaint_count);
    try std.testing.expectEqual(@as(f32, 9134), karen.anger_level);
}

test "multi multi multi" {
    var numbers: [10]usize = undefined;
    var numbers2: [10]usize = undefined;
    var numbers3: [10]usize = undefined;
    for (0..10) |i| {
        numbers[i] = i;
        numbers2[i] = i * 2;
        numbers3[i] = i * 3;
    }
    var current: usize = 0;
    for (numbers, numbers2, numbers3) |a, b, c| {
        try std.testing.expectEqual(current, a);
        try std.testing.expectEqual(current, b / 2);
        try std.testing.expectEqual(current, c / 3);
        current += 1;
    }
    var maybe_x: ?usize = 1;
    var maybe_y: ?usize = 2;
    var maybe_z: ?usize = 3;
    if (maybe_x) |x|
        if (maybe_y) |y|
            if (maybe_z) |z| {
                try std.testing.expectEqual(@as(usize, 1), x);
                try std.testing.expectEqual(@as(usize, 2), y);
                try std.testing.expectEqual(@as(usize, 3), z);
            } else {
                unreachable;
            };
}

test "optional ptrs and ptrs to optionals" {
    const Taco = struct {
        soft: bool,
        spice_level: u8,
    };

    var t0: ?Taco = Taco{ .soft = true, .spice_level = 1 };
    var t0_ptr = &t0;

    var t1: *Taco = &t0_ptr.*.?;
    t1.spice_level = 2;

    var e1: u8 = 2;
    try std.testing.expectEqual(e1, t0.?.spice_level);
    var p0 = @ptrToInt(t0_ptr);
    var p1 = @ptrToInt(t1);
    try std.testing.expectEqual(p0, p1);
}

test "undefined memory in debug build" {
    const allocator = std.testing.allocator;
    const n = 32;
    // currently zig fills allocated memory with 0xaa while in debug mode
    // e.g. this test fails with -Doptimize ReleaseFast
    var s0 = [_]u8{0xaa} ** n;
    var s1 = try std.testing.allocator.alloc(u8, n);
    defer allocator.free(s1);
    try std.testing.expect(std.mem.eql(u8, &s0, s1));
}
