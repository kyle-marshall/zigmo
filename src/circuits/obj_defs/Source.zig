const Self = @This();

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const circuit_simulator = @import("../circuit_simulator.zig");
const GateTableEntry = circuit_simulator.GateTableEntry;
const GateFactory = circuit_simulator.GateFactory;
const GateVariant = circuit_simulator.GateVariant;

const MouseButton = @import("../logiverse.zig").MouseButton;

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

const SourceVariant = enum {
    toggle,
    button,
    clock,
};

const TOGGLE_LABEL = "toggle";
const BUTTON_LABEL = "btn";

variant: SourceVariant,
pin_id: usize,
// rect is relative to handle position
color: Color,

curr_value: bool,
clock_period: f32,
clock_pulse_width: f32,

/// set to true when the mouse is pressed down on the source,
/// set to false when the mouse is released or
_click_started: bool,

pub const v_table = ObjectVTable{
    .init = Self._init,
    .spawn = Self.spawn,
    .delete = Self.delete,
    .render = Self.render,
    .update = Self.update,
    .mouseDown = Self.mouseDown,
    .mouseUp = Self.mouseUp,
    .mouseMove = NoOp.mouseMove,
    .debugPrint = NoOp.debugPrint,
};

fn init(allocator: Allocator) Self {
    _ = allocator;
    return Self{
        .variant = .toggle,
        .pin_id = 0,
        .color = raylib.WHITE,
        .curr_value = false,
        .clock_period = 1.0,
        .clock_pulse_width = 0.5,
        ._click_started = false,
    };
}

fn _init(handle: *ObjectHandle, allocator: Allocator) anyerror!Object {
    _ = handle;
    return Object{
        .source = Self.init(allocator),
    };
}

fn deinit(self: *Self) void {
    _ = self;
}

fn render(handle: *ObjectHandle, frame_time: f32) !void {
    const origin = handle.rel_bounds.origin.add(handle.position);
    const w_rect = Rect(f32).init(origin, handle.rel_bounds.size);
    const screen_rect = handle.world.cam.worldToScreenRect(w_rect);
    const obj = handle.getObject();
    var source = &obj.source;
    const fill_color = if (source.curr_value) raylib.GREEN else source.color;
    raylib.DrawRectangleV(screen_rect.origin.toRaylibVector2(), screen_rect.size.toRaylibVector2(), fill_color);
    var str = if (source.variant == .toggle) TOGGLE_LABEL else BUTTON_LABEL;
    var font_size = 5 * handle.world.cam.curr_scale;
    var center_top = screen_rect.origin.add(Vec2(f32).init(screen_rect.size.v[0] / 2, 0));
    root.gfx.drawTextCentered(str, center_top, font_size, 1, .top, raylib.BLACK);
    _ = frame_time;
}

fn spawn(handle: *ObjectHandle) !void {
    var source = &handle.getObject().source;
    const net_id = try handle.world.csim.addNet(true);
    std.debug.print("source net_id: {}\n", .{net_id});
    var pin_hdl = try handle.world.spawnObject(.pin, handle.position);
    var pin = &pin_hdl.getObject().pin;
    pin.csim_net_id = net_id;
    pin.is_primary = true;
    pin.is_connected = true;
    pin_hdl.parent_id = handle.id;
    source.pin_id = pin_hdl.obj_id;
    var r_vec = Vec2(f32).fill(10);
    handle.rel_bounds = Rect(f32).init(Vec2(f32).zero.sub(r_vec), r_vec.mulScalar(2));
}

fn update(handle: *ObjectHandle, frame_time: f32) !void {
    var source = &handle.getObject().source;
    switch (source.variant) {
        .toggle => {
            // nothing to do
        },
        .button => {
            unreachable;
        },
        .clock => {
            unreachable;
        },
    }
    _ = frame_time;

    // check if net value still matches source value (wire/pin changes may have happened)
    var pin_hdl = handle.mgr.getHandleByObjectId(.pin, source.pin_id);
    var pin = &pin_hdl.getObject().pin;

    var net = handle.world.csim.net_table.getPtr(pin.csim_net_id);
    if (net.external_signal != source.curr_value) {
        net.external_signal = source.curr_value;
    }
}

fn delete(handle: *ObjectHandle) !void {
    var source = &handle.getObject().source;
    var pin_hdl = handle.mgr.getHandleByObjectId(.pin, source.pin_id);
    try pin_hdl.delete();
}

fn mouseDown(handle: *ObjectHandle, btn: MouseButton, pos: Vec2(f32)) !void {
    _ = pos;
    if (btn != .left) return;
    var source = &handle.getObject().source;
    switch (source.variant) {
        .toggle => {
            source._click_started = true;
        },
        .button => {
            unreachable;
        },
        .clock => {
            unreachable;
        },
    }
}

fn mouseUp(handle: *ObjectHandle, btn: MouseButton, pos: Vec2(f32)) !void {
    _ = pos;
    if (btn != .left) return;
    var source = &handle.getObject().source;
    switch (source.variant) {
        .toggle => {
            std.debug.print("TOGGLE!\n", .{});
            if (source._click_started) {
                // toggle the value
                source.curr_value = !source.curr_value;
                // update the net
                var pin_hdl = handle.mgr.getHandleByObjectId(.pin, source.pin_id);
                var pin = &pin_hdl.getObject().pin;
                const net_id = pin.csim_net_id;
                const net = handle.world.csim.net_table.getPtr(net_id);
                net.external_signal = source.curr_value;
            }
        },
        .button => {
            unreachable;
        },
        .clock => {
            unreachable;
        },
    }
    source._click_started = false;
}
