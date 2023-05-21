const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const circuit_simulator = @import("../circuit_simulator.zig");
const GateTableEntry = circuit_simulator.GateTableEntry;
const GateFactory = circuit_simulator.GateFactory;
const GateVariant = circuit_simulator.GateVariant;

const root = @import("root");
const raylib = root.raylib;
const Color = raylib.Color;

const math = root.math;
const Vec2 = math.Vec2;
const Rect = math.geo.Rect;

const _obj = @import("../obj.zig");
const Object = _obj.Object;
const ObjectVTable = _obj.ObjectVTable;
const ObjectHandle = _obj.ObjectHandle;
const NoOp = _obj.NoOp;

pub const Gate = struct {
    csim_gate_id: usize,
    variant: GateVariant,
    /// owned pins will move with the component when it is moved
    owned_pins: ArrayList(usize),
    // rect is relative to handle position
    color: Color,

    const Self = @This();
    pub fn init(allocator: Allocator) Self {
        return Self{
            .variant = .AND,
            .csim_gate_id = 0,
            .owned_pins = ArrayList(usize).init(allocator),
            .color = raylib.MAGENTA,
        };
    }

    pub const v_table = ObjectVTable{
        .init = Self._init,
        .spawn = Self._spawn,
        .delete = Self._delete,
        .render = Self._render,
        .update = NoOp.update,
        .mouse_down = NoOp.mouse_down,
        .mouse_up = NoOp.mouse_up,
        .mouse_move = NoOp.mouse_move,
    };

    pub fn _init(handle: *ObjectHandle, allocator: Allocator) anyerror!Object {
        _ = handle;
        return Object{
            .gate = Self.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    fn _render(handle: *ObjectHandle, frame_time: f32) !void {
        const world_top_left = handle.position.add(handle.rel_bounds.origin);
        const world_bot_right = world_top_left.add(handle.rel_bounds.size);
        const screen_top_left = handle.world.cam.worldToScreen(world_top_left);
        const screen_bot_right = handle.world.cam.worldToScreen(world_bot_right);
        const screen_size = screen_bot_right.sub(screen_top_left);
        const obj = handle.getObject();
        var gate = &obj.gate;
        raylib.DrawRectangleV(screen_top_left.toRaylibVector2(), screen_size.toRaylibVector2(), gate.color);
        _ = frame_time;
    }

    fn _spawn(handle: *ObjectHandle) !void {
        _ = handle;
    }

    fn _delete(handle: *ObjectHandle) !void {
        // delete connected pins (pin deletion will delete wires)
        const obj = handle.getObject();
        var gate = &obj.gate;
        for (gate.owned_pins.items) |pin_id| {
            const pin_hdl = handle.mgr.getHandleByObjectId(.pin, pin_id);
            try pin_hdl.delete();
        }
    }
};
