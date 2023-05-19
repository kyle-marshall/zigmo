const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoArrayHashMap = std.AutoArrayHashMap;

const math = @import("root").math;
const Vec2 = math.Vec2;
const Rect = math.Rect;

const geo = @import("root").geo;
const RadiusQueryResultItem = geo.RadiusQueryResultItem;
const PointData = geo.PointData;

const MAX_DEPTH = 5;

pub fn QuadTreeNode(comptime KeyT: type) type {
    return struct {
        const Self = @This();
        allocator: Allocator,
        parent: ?*Self,
        max_objects: u32,
        max_levels: i32,
        bounds: Rect(f32),
        objects: AutoArrayHashMap(KeyT, PointData(f32, KeyT)),
        children: [4]*Self,
        is_divided: bool,
        key_to_node: ?AutoArrayHashMap(KeyT, *Self),

        pub fn init(allocator: Allocator, parent: ?*Self, bounds: Rect(f32), max_objects: u32, max_levels: i32) !Self {
            return Self{
                .allocator = allocator,
                .parent = parent,
                .max_objects = max_objects,
                .max_levels = max_levels,
                .bounds = bounds,
                .objects = AutoArrayHashMap(KeyT, PointData(f32, KeyT)).init(allocator),
                .children = undefined,
                .is_divided = false,
                .key_to_node = if (parent == null) AutoArrayHashMap(KeyT, *Self).init(allocator) else null,
            };
        }

        /// like init, but returns allocates memory and returns pointer to the node
        pub fn new(allocator: std.mem.Allocator, parent: ?*Self, bounds: Rect(f32), max_objects: u32, max_levels: i32) !*Self {
            var node = try allocator.create(Self);
            node.* = try Self.init(allocator, parent, bounds, max_objects, max_levels);
            return node;
        }

        fn assertNotOOB(self: *Self, point: Vec2(f32)) void {
            if (!self.bounds.containsPoint(point)) {
                std.log.err("insert - OOB:", .{});
                point.debugPrint();
                unreachable;
            }
        }

        pub fn getRoot(self: *Self) *Self {
            if (self.parent == null) {
                return self;
            }
            var parent = self.parent orelse unreachable;
            return parent.getRoot();
        }

        pub inline fn getKeyToNodeMap(self: *Self) *AutoArrayHashMap(KeyT, *Self) {
            var root = self.getRoot();
            return &(root.key_to_node orelse unreachable);
        }

        pub inline fn findNodeByKey(self: *Self, key: KeyT) ?*Self {
            return getKeyToNodeMap(self).get(key);
        }

        pub inline fn declareOwnershipOfKey(self: *Self, key: KeyT) !void {
            var map = self.getKeyToNodeMap();
            try map.put(key, self);
        }

        pub fn abandonOwnershipOfKey(self: *Self, key: KeyT) !void {
            var root = self.getRoot();
            const map = root.key_to_node orelse unreachable;
            map.remove(key);
        }

        pub fn deinit(self: *Self) void {
            if (self.children != null) {
                var children = self.children orelse unreachable;
                for (children) |*child| {
                    child.deinit();
                }
                self.allocator.free(self.children orelse unreachable);
            }
        }

        pub fn getDepth(self: *Self) u32 {
            if (self.parent == null) {
                return 0;
            }
            var parent = self.parent orelse unreachable;
            return 1 + parent.getDepth();
        }

        pub fn getLastKnownPosition(self: *Self, key: KeyT) ?Vec2(f32) {
            var maybe_point_data = self.objects.get(key);
            if (maybe_point_data == null) {
                return null;
            }
            var point_data = maybe_point_data orelse unreachable;
            return point_data.point;
        }

        pub fn divide(self: *Self) error{OutOfMemory}!void {
            if (self.is_divided or self.getDepth() >= MAX_DEPTH) {
                return;
            }
            const child_size = self.bounds.size.divScalar(2);
            const child_offsets = [_]Vec2(f32){
                Vec2(f32).zero,
                Vec2(f32).init(child_size.v[0], 0),
                Vec2(f32).init(0, child_size.v[1]),
                child_size,
            };
            const max_levels = if (self.max_levels == -1) self.max_levels else self.max_levels - 1;

            for (child_offsets, 0..) |o, i| {
                const bounds = Rect(f32).init(self.bounds.origin.add(o), child_size);
                self.children[i] = try Self.new(
                    self.allocator,
                    self,
                    bounds,
                    self.max_objects,
                    max_levels,
                );
            }

            var objects = &self.objects;
            var iter = objects.iterator();
            var maybe_entry = iter.next();
            while (maybe_entry != null) : (maybe_entry = iter.next()) {
                var entry = maybe_entry orelse unreachable;
                var point_data = entry.value_ptr.*;
                for (self.children) |child| {
                    if (child.bounds.containsPoint(point_data.point)) {
                        try child.insert(point_data.point, point_data.data);
                        break;
                    }
                }
            }

            objects.clearAndFree();
            self.is_divided = true;
        }

        pub fn insert(self: *Self, point: Vec2(f32), data: KeyT) !void {
            self.assertNotOOB(point);

            if (self.is_divided) {
                for (self.children) |child| {
                    if (child.bounds.containsPoint(point)) {
                        try child.insert(point, data);
                        return;
                    }
                }
                unreachable;
            }

            var objects = &self.objects;
            // std.debug.print("insert - adding object {d}\n", .{self.objects.v.len});
            try objects.put(data, PointData(f32, KeyT){
                .point = point,
                .data = data,
            });
            try self.declareOwnershipOfKey(data);

            std.debug.assert(self.objects.get(data) != null);
            if (self.objects.count() > self.max_objects and
                (self.max_levels == -1 or self.max_levels > 0))
            {
                try self.divide();
            }

            std.debug.assert(self.findNodeByKey(data) != null);
        }

        pub fn removeOwnedObject(self: *Self, index: usize) ?PointData(f32, KeyT) {
            if (self.is_divided) {
                std.log.warn("removeOwnedObject - node is divided", .{});
                return null;
            }

            return self.objects.swapRemove(index);
        }

        pub fn remove(self: *Self, data: KeyT) !void {
            var node = self.findNodeByKey(data);
            if (node == null) {
                std.log.warn("remove - parent node not found", .{});
                return;
            }
            var index = node.findOwnedObjectIndex(data) orelse unreachable;
            var item = node.removeOwnedObject(index) orelse unreachable;
            _ = item;
        }

        pub fn findOwnedObjectIndex(self: *Self, target: PointData(f32, KeyT)) ?usize {
            if (self.is_divided) return null;
            var index: usize = 0;
            while (index < self.objects.items.len) : (index += 1) {
                var item = self.objects.items[index];
                if (target.equals(item)) {
                    return index;
                }
            }
            return null;
        }

        pub fn findChildContainingPoint(self: *Self, point: Vec2(f32)) *Self {
            if (self.is_divided) {
                for (self.children) |child| {
                    if (child.bounds.containsPoint(point)) {
                        return child;
                    }
                }
                unreachable;
            }
            return self;
        }

        pub fn move(self: *Self, data: KeyT, new_point: Vec2(f32)) !void {
            self.assertNotOOB(new_point);
            var maybe_node = self.findNodeByKey(data);
            if (maybe_node == null) {
                unreachable;
            }
            var node = maybe_node orelse unreachable;
            if (node.bounds.containsPoint(new_point)) {
                // we don't need to remove/reinsert the object, just update the point
                try node.objects.put(data, PointData(f32, KeyT){
                    .point = new_point,
                    .data = data,
                });
            } else {
                // we need to remove/reinsert the object
                _ = node.objects.swapRemove(data);
                try self.getRoot().insert(new_point, data);
            }
        }

        fn _query(self: *Self, allocator: std.mem.Allocator, query_point: Vec2(f32), search_radius: f32, results_list: *ArrayList(RadiusQueryResultItem(f32, KeyT)), depth: u32) !void {
            if (self.is_divided) {
                const pad_vec = Vec2(f32).fill(search_radius);
                const padded_size = self.children[0].bounds.size.add(pad_vec).add(pad_vec);
                for (self.children) |child| {
                    const padded_bounds = Rect(f32){
                        .origin = child.bounds.origin.sub(pad_vec),
                        .size = padded_size,
                    };
                    if (padded_bounds.containsPoint(query_point)) {
                        try child._query(allocator, query_point, search_radius, results_list, depth + 1);
                    }
                }
            }

            var objects = &self.objects;
            var iter = objects.iterator();
            var maybe_entry = iter.next();
            while (maybe_entry != null) : (maybe_entry = iter.next()) {
                var entry = maybe_entry orelse unreachable;
                var point_data = entry.value_ptr.*;
                const diff = point_data.point.sub(query_point);
                const d = diff.getMagnitude();
                if (d <= search_radius) {
                    try results_list.append(RadiusQueryResultItem(f32, KeyT){ .point_data = point_data, .distance = d });
                }
            }
        }

        pub fn query(self: *Self, allocator: std.mem.Allocator, query_point: Vec2(f32), search_radius: f32) !ArrayList(RadiusQueryResultItem(f32, KeyT)) {
            var results_list = try ArrayList(RadiusQueryResultItem(f32, KeyT)).initCapacity(allocator, self.max_objects);
            try self._query(allocator, query_point, search_radius, &results_list, 0);
            return results_list;
        }

        pub fn debugPrintOwnedObjects(self: *Self) void {
            std.debug.print("owned objects: {d}\n", .{self.objects.items.len});
            for (self.objects.items) |item| {
                std.debug.print("  ({d}, {d}): {d}\n", .{ item.point.v[0], item.point.v[1], item.data });
            }
        }
    };
}
