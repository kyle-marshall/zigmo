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
    /// these are HANDLE ids
    owned_pins: ArrayList(usize),
    // rect is relative to handle position
    color: Color,

    const _dbg_print_ignore_props = [_][]const u8{
        "owned_pins",
    };

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
        .spawn = Self.spawn,
        .delete = Self.delete,
        .render = Self.render,
        .update = NoOp.update,
        .mouseDown = NoOp.mouseDown,
        .mouseUp = NoOp.mouseUp,
        .mouseMove = NoOp.mouseMove,
        .debugPrint = Self.debugPrint,
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

    fn render(handle: *ObjectHandle, frame_time: f32) !void {
        const origin = handle.rel_bounds.origin.add(handle.position);
        const w_rect = Rect(f32).init(origin, handle.rel_bounds.size);
        const screen_rect = handle.world.cam.worldToScreenRect(w_rect);
        const obj = handle.getObject();
        var gate = &obj.gate;
        raylib.DrawRectangleV(screen_rect.origin.toRaylibVector2(), screen_rect.size.toRaylibVector2(), gate.color);
        _ = frame_time;
    }

    fn spawn(handle: *ObjectHandle) !void {
        _ = handle;
    }

    fn delete(handle: *ObjectHandle) !void {
        // delete connected pins (pin deletion will delete wires)
        const obj = handle.getObject();
        var gate = &obj.gate;
        for (gate.owned_pins.items) |pin_id| {
            std.debug.print("Gate.delete deleting pin {}\n", .{pin_id});
            const pin_hdl = handle.mgr.getHandle(pin_id);
            try pin_hdl.delete();
        }
        // delete csim representation
        try handle.world.csim.freeGate(gate.csim_gate_id);
    }

    pub fn debugPrint(handle: *ObjectHandle) !void {
        const obj = handle.getObject();
        const gate = &obj.gate;
        root.util.debugPrintObjectIgnoringFields(Self, gate, Self._dbg_print_ignore_props);
    }
};
