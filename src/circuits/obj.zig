const std = @import("std");
const AutoHashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;

const logiverse = @import("./logiverse.zig");
const Logiverse = logiverse.Logiverse;
const MouseButton = logiverse.MouseButton;

const root = @import("root");
const ObjectStore = root.ObjectStore;
const math = root.math;
const Vec2 = math.Vec2;
const Rect = math.geo.Rect;

const Pin = @import("obj_defs/Pin.zig");
const Wire = @import("obj_defs/Wire.zig");
const Gate = @import("obj_defs/Gate.zig");
const Source = @import("obj_defs/Source.zig");

pub const ObjectVariant = enum { pin, wire, gate, source };
const NUM_VARIANTS = 4;
pub const Object = union {
    pin: Pin,
    wire: Wire,
    gate: Gate,
    source: Source,
};

pub const ObjectVTable = struct {
    init: *const fn (*ObjectHandle, allocator: Allocator) anyerror!Object,
    spawn: *const fn (*ObjectHandle) anyerror!void,
    delete: *const fn (*ObjectHandle) anyerror!void,
    render: *const fn (*ObjectHandle, f32) anyerror!void,
    update: *const fn (*ObjectHandle, f32) anyerror!void,

    mouseDown: *const fn (*ObjectHandle, btn: MouseButton, world_pos: Vec2(f32)) anyerror!void,
    mouseUp: *const fn (*ObjectHandle, btn: MouseButton, world_pos: Vec2(f32)) anyerror!void,
    mouseMove: *const fn (*ObjectHandle, world_pos: Vec2(f32)) anyerror!void,

    debugPrint: *const fn (*ObjectHandle) anyerror!void,
};

pub const ObjectManager = struct {
    allocator: Allocator,
    handles: ObjectStore(ObjectHandle),
    stores: [NUM_VARIANTS]ObjectStore(Object),
    v_tables: [NUM_VARIANTS]ObjectVTable,
    /// reverse_lookup maps object ids to handle ids
    reverse_lookup: [NUM_VARIANTS]AutoHashMap(usize, usize),
    const Self = @This();
    pub fn init(allocator: Allocator) !Self {
        var stores: [NUM_VARIANTS]ObjectStore(Object) = undefined;
        var reverse_lookup: [NUM_VARIANTS]AutoHashMap(usize, usize) = undefined;
        for (0..NUM_VARIANTS) |i| {
            stores[i] = ObjectStore(Object).init(allocator);
            reverse_lookup[i] = AutoHashMap(usize, usize).init(allocator);
        }
        return Self{
            .allocator = allocator,
            .handles = ObjectStore(ObjectHandle).init(allocator),
            .v_tables = [_]ObjectVTable{
                Pin.v_table,
                Wire.v_table,
                Gate.v_table,
                Source.v_table,
            },
            .stores = stores,
            .reverse_lookup = reverse_lookup,
        };
    }
    pub fn deinit(self: *Self) !void {
        for (self.stores) |store| {
            try store.deinit();
        }
    }
    pub inline fn getStore(self: *Self, variant: ObjectVariant) *ObjectStore(Object) {
        return &self.stores[@enumToInt(variant)];
    }
    pub inline fn getHandle(self: *Self, handle_id: usize) *ObjectHandle {
        return self.handles.getPtr(handle_id);
    }
    pub inline fn getHandleByObjectId(self: *Self, variant: ObjectVariant, obj_id: usize) *ObjectHandle {
        var h_id = self.reverse_lookup[@enumToInt(variant)].get(obj_id) orelse {
            std.debug.panic("ObjectManager.getHandleByObjectId: no handle found for object id {} {d}\n", .{ variant, obj_id });
            unreachable;
        };
        return self.getHandle(h_id);
    }
    pub fn createHandle(self: *Self, variant: ObjectVariant) !*ObjectHandle {
        const h_id = try self.handles.store(ObjectHandle{
            .id = 0,
            .mgr = self,
            .world = undefined,
            .variant = variant,
            .obj_id = 0,
            .position = Vec2(f32).zero,
            .rel_bounds = Rect(f32).init(Vec2(f32).zero, Vec2(f32).one),
            .v_table = &self.v_tables[@enumToInt(variant)],
            .parent_id = null,
        });
        var handle = self.getHandle(h_id);
        handle.id = h_id;
        var store = self.getStore(variant);
        const obj_id = try store.store(try handle.init(self.allocator));
        handle.obj_id = obj_id;
        try self.reverse_lookup[@enumToInt(variant)].put(obj_id, h_id);
        return handle;
    }
};

pub const ObjectHandle = struct {
    id: usize,
    mgr: *ObjectManager,
    world: *Logiverse,
    variant: ObjectVariant,
    // obj_id is the object's id in it's respective store
    obj_id: usize,
    position: Vec2(f32),
    // bounds relative to position, e.g. does not change when position changes
    rel_bounds: Rect(f32),

    v_table: *const ObjectVTable,
    parent_id: ?usize,

    const Self = @This();
    pub inline fn init(self: *Self, allocator: Allocator) !Object {
        return self.v_table.init(self, allocator);
    }
    pub inline fn spawn(self: *Self) !void {
        try self.v_table.spawn(self);
    }
    pub inline fn delete(self: *Self) !void {
        _ = self.world.spatial_hash.remove(self.id);
        // std.debug.print("DELETE START {d} ({?} {d})\n", .{ self.id, self.variant, self.obj_id });
        try self.v_table.delete(self);
        try self.mgr.getStore(self.variant).remove(self.obj_id);
        try self.mgr.handles.remove(self.id);
        std.debug.print("deleted {d} ({?} {d})\n", .{ self.id, self.variant, self.obj_id });
    }
    pub inline fn render(self: *Self, delta: f32) !void {
        try self.v_table.render(self, delta);
    }
    pub inline fn update(self: *Self, delta: f32) !void {
        try self.v_table.update(self, delta);
    }

    pub inline fn mouseDown(self: *Self, btn: MouseButton, world_pos: Vec2(f32)) !void {
        try self.v_table.mouseDown(self, btn, world_pos);
    }
    pub inline fn mouseUp(self: *Self, btn: MouseButton, world_pos: Vec2(f32)) !void {
        try self.v_table.mouseUp(self, btn, world_pos);
    }
    pub inline fn mouseMove(self: *Self, world_pos: Vec2(f32)) !void {
        try self.v_table.mouseMove(self, world_pos);
    }

    pub inline fn debugPrint(self: *Self) !void {
        try self.v_table.debugPrint(self);
    }

    pub inline fn getObject(self: *Self) *Object {
        return self.mgr.getStore(self.variant).getPtr(self.obj_id);
    }
    pub inline fn getStore(self: *Self) *ObjectStore(Object) {
        return self.mgr.getStore(self.variant);
    }

    pub inline fn containsPoint(self: *Self, world_pos: Vec2(f32)) bool {
        const d = world_pos - self.position;
        return self.rel_bounds.containsPoint(d);
    }
};

pub const NoOp = struct {
    const Self = @This();
    pub const v_table = ObjectVTable{
        .init = Self.init,
        .spawn = Self.spawn,
        .delete = Self.delete,
        .render = Self.render,
        .update = Self.update,
        .mouseDown = Self.mouseDown,
        .mouseUp = Self.mouseUp,
        .mouseMove = Self.mouseMove,
        .debugPrint = Self.debugPrint,
    };
    pub fn init(handle: *ObjectHandle, allocator: Allocator) !Object {
        _ = handle;
        _ = allocator;
        unreachable;
    }
    pub fn spawn(handle: *ObjectHandle) !void {
        _ = handle;
    }
    pub fn delete(handle: *ObjectHandle) !void {
        _ = handle;
    }
    pub fn render(handle: *ObjectHandle, delta: f32) !void {
        _ = handle;
        _ = delta;
    }
    pub fn update(handle: *ObjectHandle, delta: f32) !void {
        _ = handle;
        _ = delta;
    }
    pub fn mouseDown(handle: *ObjectHandle, btn: MouseButton, world_pos: Vec2(f32)) !void {
        _ = handle;
        _ = btn;
        _ = world_pos;
    }
    pub fn mouseUp(handle: *ObjectHandle, btn: MouseButton, world_pos: Vec2(f32)) !void {
        _ = handle;
        _ = btn;
        _ = world_pos;
    }
    pub fn mouseMove(handle: *ObjectHandle, world_pos: Vec2(f32)) !void {
        _ = handle;
        _ = world_pos;
    }
    pub fn debugPrint(handle: *ObjectHandle) !void {
        _ = handle;
    }
};
