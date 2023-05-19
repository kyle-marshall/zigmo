const std = @import("std");
const ArrayList = std.ArrayList;
const AutoArrayHashMap = std.AutoArrayHashMap;
const AutoHashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;

const math = @import("root").math;
const Rect = math.geo.Rect;
const Vec2 = math.Vec2;

const geo = @import("geo.zig");
const PointData = geo.PointData;
const RadiusQueryResultItem = geo.RadiusQueryResultItem;

pub fn SpatialHashCell(comptime NumT: type, comptime KeyT: type) type {
    return struct {
        bounds: Rect(NumT),
        objects: AutoArrayHashMap(KeyT, PointData(NumT, KeyT)),

        const Self = @This();

        pub fn init(allocator: Allocator, bounds: Rect(NumT)) Self {
            return Self{
                .bounds = bounds,
                .objects = AutoArrayHashMap(KeyT, PointData(NumT, KeyT)).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn insert(self: *Self, pos: Vec2(NumT), key: KeyT) !void {
            var objects = &self.objects;
            try objects.put(
                key,
                PointData(NumT, KeyT){ .point = pos, .data = key },
            );
        }

        pub fn query(
            self: *Self,
            pos: Vec2(NumT),
            radius: NumT,
            results: *ArrayList(RadiusQueryResultItem(NumT, KeyT)),
        ) !void {
            var objects = &self.objects;
            var iter = objects.iterator();
            var maybe_entry = iter.next();
            while (maybe_entry != null) : (maybe_entry = iter.next()) {
                var entry = maybe_entry orelse unreachable;
                var point_data = entry.value_ptr.*;
                const diff = point_data.point.sub(pos);
                const d = diff.mag();
                if (d <= radius) {
                    try results.append(RadiusQueryResultItem(NumT, KeyT){
                        .point_data = point_data,
                        .distance = d,
                    });
                }
            }
        }

        pub fn removeByKey(self: *Self, key: KeyT) bool {
            var objects = &self.objects;
            return objects.swapRemove(key);
        }

        pub fn updatePosition(self: *Self, key: KeyT, new_pos: Vec2(NumT)) !bool {
            var objects = &self.objects;
            var maybe_entry = objects.get(key);
            if (maybe_entry == null) {
                return false;
            }
            var entry = maybe_entry orelse unreachable;
            entry.point = new_pos;
            try objects.put(key, entry);
            return true;
        }
    };
}

pub fn SpatialHash(comptime NumT: type, comptime KeyT: type) type {
    return struct {
        bounds: Rect(NumT),
        cell_side_len: NumT,
        grid_size: Vec2(u32),
        cells: CellListT,
        key_to_cell_index: AutoHashMap(KeyT, usize),

        const Self = @This();
        const CellT = SpatialHashCell(NumT, KeyT);
        const CellListT = ArrayList(CellT);

        pub fn init(allocator: Allocator, bounds: Rect(NumT), search_radius: NumT) !Self {
            var cell_side_len = search_radius * 3;
            var grid_size_f = bounds.size.divScalar(cell_side_len);
            const grid_size = grid_size_f.ceilInPlace().floatToInt(u32);
            std.log.debug(
                "SpatialHash initialized with grid size: ({d}, {d})",
                .{ grid_size.v[0], grid_size.v[1] },
            );
            var s = Self{
                .bounds = bounds,
                .cell_side_len = cell_side_len,
                .grid_size = grid_size,
                .cells = CellListT.init(allocator),
                .key_to_cell_index = AutoHashMap(KeyT, usize).init(allocator),
            };
            var num_cells = grid_size.v[0] * grid_size.v[1];
            var i: u32 = 0;
            while (i < num_cells) : (i += 1) {
                const cell_coord = s.cellIndexToCoord(i);
                const size = Vec2(NumT).fill(cell_side_len);
                var origin = Vec2(NumT).init(
                    @intToFloat(NumT, cell_coord.v[0]),
                    @intToFloat(NumT, cell_coord.v[1]) * cell_side_len,
                );
                _ = origin.scaleInPlace(cell_side_len);
                const cell_bounds = Rect(NumT).init(origin, size);
                try s.cells.append(CellT.init(allocator, cell_bounds));
            }
            return s;
        }

        pub fn deinit(self: *Self) void {
            for (self.cells.items) |*cell| {
                cell.deinit();
            }
            self.cells.deinit();
        }

        pub fn cellCoordToIndex(self: *Self, coord: Vec2(u32)) u32 {
            return coord.v[1] * self.grid_size.v[0] + coord.v[0];
        }

        pub fn cellIndexToCoord(self: *Self, i: u32) Vec2(u32) {
            return Vec2(u32).init(i / self.grid_size.v[0], @mod(i, self.grid_size.v[0]));
        }

        pub fn worldPositionToCellIndex(self: *Self, pos: Vec2(NumT)) u32 {
            var coord = pos.divScalar(self.cell_side_len);
            _ = coord.floorInPlace();
            return self.cellCoordToIndex(coord.floatToInt(u32));
        }

        pub fn insert(self: *Self, pos: Vec2(NumT), data: KeyT) !bool {
            if (!self.bounds.containsPoint(pos)) {
                return false;
            }
            const index = self.worldPositionToCellIndex(pos);
            const cell = &self.cells.items[index];
            try cell.insert(pos, data);
            try self.key_to_cell_index.put(data, index);
            return true;
        }

        pub fn move(self: *Self, key: KeyT, new_pos: Vec2(NumT)) !bool {
            if (!self.bounds.containsPoint(new_pos)) {
                return false;
            }
            const old_index = self.key_to_cell_index.get(key) orelse unreachable;
            const new_index = self.worldPositionToCellIndex(new_pos);

            var old_cell = &self.cells.items[old_index];
            if (old_index == new_index) {
                _ = try old_cell.updatePosition(key, new_pos);
                return true;
            }
            if (old_cell.removeByKey(key)) {
                var new_cell = &self.cells.items[new_index];
                try new_cell.insert(new_pos, key);
                try self.key_to_cell_index.put(key, new_index);
                return true;
            }
            unreachable;
        }

        pub fn getAdjacentIndices(self: *Self, around_index: u32, results: *std.ArrayList(u32)) !void {
            const ref_cell_coord = self.cellIndexToCoord(around_index).intCast(i32);

            // const t0 = std.time.microTimestamp();
            var x_offset: i32 = -1;
            const world_origin = Vec2(i32).zero;
            while (x_offset <= 1) : (x_offset += 1) {
                var y_offset: i32 = -1;
                while (y_offset <= 1) : (y_offset += 1) {
                    if (x_offset == 0 and y_offset == 0) continue;
                    var cell_coord_i = Vec2(i32).init(x_offset, y_offset);
                    _ = cell_coord_i.addInPlace(ref_cell_coord);
                    if (@reduce(.Or, cell_coord_i.v < world_origin.v) or
                        @reduce(.Or, cell_coord_i.v >= self.grid_size.v))
                    {
                        continue;
                    }
                    const cell_coord_u = cell_coord_i.intCast(u32);
                    const index = self.cellCoordToIndex(cell_coord_u);
                    try results.append(index);
                }
            }
            // const t1 = std.time.microTimestamp();
            // std.debug.print("neighbor indexes computed in {} microseconds.\n", .{t1 - t0});
        }

        pub fn query(self: *Self, allocator: Allocator, pos: Vec2(NumT), search_radius: NumT) !ArrayList(RadiusQueryResultItem(NumT, KeyT)) {
            const cell_index = self.worldPositionToCellIndex(pos);
            var index_list = try ArrayList(u32).initCapacity(allocator, 8);
            defer index_list.deinit();
            try index_list.append(cell_index);
            try self.getAdjacentIndices(cell_index, &index_list);
            var results_list = ArrayList(RadiusQueryResultItem(NumT, KeyT)).init(allocator);
            for (index_list.items) |index| {
                try self.cells.items[index].query(pos, search_radius, &results_list);
            }
            return results_list;
        }

        pub fn querySlow(self: *Self, allocator: Allocator, pos: Vec2(NumT)) !ArrayList(RadiusQueryResultItem(NumT, KeyT)) {
            var results_list = ArrayList(RadiusQueryResultItem(NumT, KeyT)).init(allocator);
            for (self.cells.v) |*cell| {
                if (cell.bounds.getPadded(self.search_radius).containsPoint(pos)) {
                    try cell.query(pos, self.search_radius, &results_list);
                }
            }
            return results_list;
        }
    };
}
