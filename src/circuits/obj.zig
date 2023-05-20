const logiverse = @import("./logiverse.zig");
const Logiverse = logiverse.Logiverse;

const root = @import("root");
const math = root.math;
const Vec2 = math.Vec2;
const Rect = math.geo.Rect;

pub const ObjectVariant = enum { pin, wire, component };

pub const ObjectHandle = struct {
    id: usize,
    variant: ObjectVariant,
    // obj_id is the object's id in it's respective store
    obj_id: usize,
    position: Vec2(f32),
    // bounds relative to position, e.g. does not change when position changes
    rel_bounds: Rect(f32),
};

pub const ObjectFnTable = struct {
    spawn: *const fn (*Logiverse, *ObjectHandle) anyerror!usize,
    delete: *const fn (*Logiverse, *ObjectHandle) anyerror!void,
    render: *const fn (*Logiverse, *ObjectHandle, f32) anyerror!void,
    update: *const fn (*Logiverse, *ObjectHandle, f32) anyerror!void,
};

pub const NoopObjFns = struct {
    pub fn spawn(world: *Logiverse, handle: *ObjectHandle) !usize {
        _ = world;
        _ = handle;
        return 0;
    }
    pub fn delete(world: *Logiverse, handle: *ObjectHandle) !void {
        _ = world;
        _ = handle;
    }
    pub fn render(world: *Logiverse, handle: *ObjectHandle, delta: f32) !void {
        _ = world;
        _ = handle;
        _ = delta;
    }
    pub fn update(world: *Logiverse, handle: *ObjectHandle, delta: f32) !void {
        _ = world;
        _ = handle;
        _ = delta;
    }
};
