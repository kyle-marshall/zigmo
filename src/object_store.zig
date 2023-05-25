const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoArrayHashMap = std.AutoArrayHashMap;

fn ObjectStoreIterator(comptime T: type) type {
    return struct {
        store: *ObjectStore(T),
        index: usize,
        inner_slice: []T,
        mask: []bool,
        const Self = @This();
        pub fn init(store: *ObjectStore(T)) Self {
            return Self{
                .store = store,
                .index = 0,
                .inner_slice = store.inner_list.items,
                .mask = store.mask.items,
            };
        }
        pub fn next(self: *ObjectStoreIterator(T)) ?*T {
            const S = self.inner_slice;
            const M = self.mask;
            while (true) {
                var i = self.index;
                self.index += 1;
                if (i >= S.len) return null;
                if (M[i]) return &S[i];
            }
            unreachable;
        }
    };
}

fn ObjectStoreIdIterator(comptime T: type) type {
    return struct {
        store: *ObjectStore(T),
        index: usize,
        mask: []bool,
        const Self = @This();
        pub fn init(store: *ObjectStore(T)) Self {
            return Self{
                .store = store,
                .index = 0,
                .mask = store.mask.items,
            };
        }
        pub fn next(self: *ObjectStoreIdIterator(T)) ?usize {
            const M = self.mask;
            while (true) {
                var i = self.index;
                self.index += 1;
                if (i >= M.len) return null;
                if (M[i]) return i;
            }
            unreachable;
        }
    };
}

pub fn ObjectStore(comptime T: type) type {
    return struct {
        const Self = @This();
        inner_list: ArrayList(T),
        free_ids: AutoArrayHashMap(usize, void),
        mask: ArrayList(bool),

        pub fn init(allocator: Allocator) Self {
            return Self{
                .inner_list = ArrayList(T).init(allocator),
                .free_ids = AutoArrayHashMap(usize, void).init(allocator),
                .mask = ArrayList(bool).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.inner_list.deinit();
            self.free_ids.deinit();
            self.mask.deinit();
        }

        pub inline fn get(self: *Self, id: usize) T {
            return self.inner_list.items[id];
        }

        pub inline fn getPtr(self: *Self, id: usize) *T {
            return &self.inner_list.items[id];
        }

        /// assumes caller checked free_ids is not empty
        pub fn nextFreeId(self: *Self) usize {
            var iter = self.free_ids.iterator();
            return iter.next().?.key_ptr.*;
        }

        pub fn store(self: *Self, obj: T) !usize {
            const free_id_count = self.free_ids.count();
            var id: usize = undefined;
            if (free_id_count > 0) {
                id = self.nextFreeId();
                _ = self.free_ids.swapRemove(id);
                self.inner_list.items[id] = obj;
                self.mask.items[id] = true;
            } else {
                id = self.inner_list.items.len;
                try self.inner_list.append(obj);
                try self.mask.append(true);
            }
            return id;
        }

        pub inline fn remove(self: *Self, id: usize) !void {
            try self.free_ids.put(id, {});
            self.mask.items[id] = false;
        }

        pub fn iterator(self: *Self) ObjectStoreIterator(T) {
            return ObjectStoreIterator(T).init(self);
        }

        pub fn idIterator(self: *Self) ObjectStoreIdIterator(T) {
            return ObjectStoreIdIterator(T).init(self);
        }
    };
}
