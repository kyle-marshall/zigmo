const std = @import("std");
const math = @import("root").math;
pub const quad_tree = @import("quad_tree.zig");
pub const spatial_hash = @import("spatial_hash.zig");
pub const Rect = @import("rect.zig").Rect;

const Vec2 = math.Vec2;
pub fn PointData(comptime NumT: type, comptime DataT: type) type {
    return struct {
        const Self = @This();
        point: Vec2(NumT),
        data: DataT,
        pub fn equals(self: Self, other: Self) bool {
            return @reduce(.And, self.point.v == other.point.v) and self.data == other.data;
        }
    };
}

pub fn RadiusQueryResultItem(comptime NumT: type, comptime DataT: type) type {
    return struct { point_data: PointData(NumT, DataT), distance: NumT };
}

pub fn doRadiusQueryBenchmark() !void {
    const enable_spatial_hash = true;
    const enable_quad_tree = true;
    std.debug.print("Vec2 size: {d}\n", .{@sizeOf(Vec2(f32))});
    const TestPointData = PointData(f32, i32);
    const TestQueryResultsItem = RadiusQueryResultItem(f32, i32);
    var allocator = std.heap.c_allocator;
    var random_seed = std.crypto.random.int(u64);
    _ = random_seed;
    var rng = std.rand.DefaultPrng.init(99);

    const world_size = Vec2(f32).init(800, 600);

    var origin = Vec2(f32).zero;

    var screenBounds = Rect(f32).init(origin, world_size);
    screenBounds.debugPrint();
    var query_point = Vec2(f32).init(500, 500);
    var search_radius: f32 = 50;

    var hash = try spatial_hash.SpatialHash(f32, i32).init(allocator, screenBounds, search_radius);
    defer hash.deinit();

    var qt = try quad_tree.QuadTreeNode(i32).init(allocator, null, Rect(f32){
        .origin = Vec2(f32).zero,
        .size = world_size,
    }, 1000, -1);

    const num_tests: u32 = 10_000_000;
    var test_points = try std.ArrayList(TestPointData).initCapacity(allocator, num_tests);
    {
        const t0 = std.time.microTimestamp();
        var i: u32 = 0;
        while (i < num_tests) : (i += 1) {
            var point = Vec2(f32).init(rng.random().float(f32), rng.random().float(f32));
            _ = point.mulInPlace(world_size);
            const data = rng.random().int(i32);
            try test_points.append(TestPointData{ .point = point, .data = data });
        }
        const t1 = std.time.microTimestamp();
        std.debug.print("Generated test points in {d} microseconds.\n", .{t1 - t0});
    }

    if (enable_spatial_hash) {
        const t0 = std.time.microTimestamp();
        for (test_points.items) |point_data| {
            _ = try hash.insert(point_data.point, point_data.data);
        }
        const t1 = std.time.microTimestamp();
        std.debug.print("Prepared {s} in {d} microseconds.\n", .{ @typeName(@TypeOf(hash)), t1 - t0 });
    }

    if (enable_quad_tree) {
        const t0 = std.time.microTimestamp();
        for (test_points.items) |point_data| {
            try qt.insert(point_data.point, point_data.data);
        }
        const t1 = std.time.microTimestamp();
        std.debug.print("Prepared {s} in {d} microseconds.\n", .{ @typeName(@TypeOf(qt)), t1 - t0 });
    }

    if (enable_spatial_hash) {
        const t0 = std.time.microTimestamp();
        var results = try hash.query(allocator, query_point);
        const t1 = std.time.microTimestamp();
        std.debug.print("Queried {d} results in {d} microseconds (SpatialHash).\n", .{ results.items.len, t1 - t0 });
    }

    if (enable_quad_tree) {
        const t0 = std.time.microTimestamp();
        var results = try qt.query(allocator, query_point, search_radius);
        const t1 = std.time.microTimestamp();
        std.debug.print("Queried {} results in {} microseconds (QuadTree).\n", .{ results.items.len, t1 - t0 });
    }

    {
        const t0 = std.time.microTimestamp();
        var results = std.ArrayList(TestQueryResultsItem).init(allocator);
        for (test_points.items) |item| {
            const d = Vec2(f32).distanceBetween(item.point, query_point);
            if (d <= search_radius) {
                try results.append(TestQueryResultsItem{ .point_data = item, .distance = d });
            }
        }
        const t1 = std.time.microTimestamp();
        std.debug.print("Queried {} results in {} microseconds (ArrayList).\n", .{ results.items.len, t1 - t0 });
    }
}

pub fn doRadiusQueryBenchmark2() !void {
    std.debug.print("Vec2 size: {d}\n", .{@sizeOf(Vec2(f32))});

    const PlainStructVec = struct { x: f32, y: f32 };

    const TestPointData = PointData(f32, i32);
    const AltPointData = struct { point: @Vector(2, f32), data: i32 };
    const AltPointData2 = struct { point: PlainStructVec, data: i32 };

    const TestQueryResultsItem = RadiusQueryResultItem(f32, i32);
    _ = TestQueryResultsItem;
    var allocator = std.heap.c_allocator;
    var random_seed = std.crypto.random.int(u64);
    _ = random_seed;
    var rng = std.rand.DefaultPrng.init(99);

    const world_size = Vec2(f32).fromItems(.{ 800, 600 });

    var origin = Vec2(f32).zero;

    var screenBounds = Rect(f32).init(origin, world_size);
    screenBounds.debugPrint();
    var query_point = Vec2(f32).fromItems(.{ 500, 500 });
    var search_radius: f32 = 50;

    const num_tests: u32 = 10_000_000;
    var test_points_a = try std.ArrayList(TestPointData).initCapacity(allocator, num_tests);
    var test_points_d = try std.ArrayList(TestPointData).initCapacity(allocator, num_tests);
    var test_points_b = try std.ArrayList(AltPointData).initCapacity(allocator, num_tests);
    var test_points_c = try std.ArrayList(AltPointData2).initCapacity(allocator, num_tests);

    {
        const t0 = std.time.microTimestamp();
        var i: u32 = 0;
        while (i < num_tests) : (i += 1) {
            var point = Vec2(f32).fromItems(.{ rng.random().float(f32), rng.random().float(f32) });
            _ = point.mulInPlace(world_size);
            const data = rng.random().int(i32);
            try test_points_a.append(TestPointData{ .point = point, .data = data });
            try test_points_d.append(TestPointData{ .point = point, .data = data });
            try test_points_b.append(AltPointData{ .point = point.v, .data = data });
            const plain_point = PlainStructVec{ .x = point.v[0], .y = point.v[1] };
            try test_points_c.append(AltPointData2{ .point = plain_point, .data = data });
        }
        const t1 = std.time.microTimestamp();
        std.debug.print("Generated test points in {d} microseconds.\n", .{t1 - t0});
    }

    {
        const t0 = std.time.microTimestamp();
        var count: u32 = 0;
        const qp = query_point.v;
        for (test_points_b.v) |item| {
            const diff = item.point - qp;
            const d = @sqrt(@reduce(.Add, diff * diff));
            if (d <= search_radius) {
                count += 1;
            }
        }
        const t1 = std.time.microTimestamp();
        std.debug.print("Queried {d} results in {d} microseconds (AltPointData).\n", .{ count, t1 - t0 });
    }

    {
        const t0 = std.time.microTimestamp();
        var count: u32 = 0;
        const qp = PlainStructVec{ .x = query_point.v[0], .y = query_point.v[1] };
        for (test_points_c.v) |item| {
            const diff_x = item.point.x - qp.x;
            const diff_y = item.point.y - qp.y;
            const d = @sqrt(diff_x * diff_x + diff_y * diff_y);
            if (d <= search_radius) {
                count += 1;
            }
        }
        const t1 = std.time.microTimestamp();
        std.debug.print("Queried {d} results in {d} microseconds (PlainStructVec).\n", .{ count, t1 - t0 });
    }

    {
        const t0 = std.time.microTimestamp();
        var count: u32 = 0;
        for (test_points_d.v) |item| {
            const diff = item.point.sub(query_point);
            const d = diff.getMagnitude();
            if (d <= search_radius) {
                count += 1;
            }
        }
        const t1 = std.time.microTimestamp();
        std.debug.print("Queried {d} results in {d} microseconds (TestPointData).\n", .{ count, t1 - t0 });
    }

    {
        const t0 = std.time.microTimestamp();
        var count: u32 = 0;
        for (test_points_a.v) |item| {
            const d = Vec2(f32).distanceBetween(item.point, query_point);
            if (d <= search_radius) {
                count += 1;
            }
        }
        const t1 = std.time.microTimestamp();
        std.debug.print("Queried {d} results in {d} microseconds (TestPointData*).\n", .{ count, t1 - t0 });
    }
}
