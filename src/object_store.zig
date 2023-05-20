const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

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

pub fn ObjectStore(comptime T: type) type {
    return struct {
        const Self = @This();
        inner_list: ArrayList(T),
        free_ids: ArrayList(usize),
        mask: ArrayList(bool),

        pub fn init(allocator: Allocator) Self {
            return Self{
                .inner_list = ArrayList(T).init(allocator),
                .free_ids = ArrayList(usize).init(allocator),
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

        pub inline fn store(self: *Self, obj: T) !usize {
            var id: usize = undefined;
            if (self.free_ids.items.len > 0) {
                id = self.free_ids.pop();
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
            try self.free_ids.append(id);
            self.mask.items[id] = false;
        }

        pub fn iterator(self: *Self) ObjectStoreIterator(T) {
            return ObjectStoreIterator(T).init(self);
        }
    };
}
