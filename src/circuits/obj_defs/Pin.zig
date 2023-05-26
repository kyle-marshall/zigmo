const Self = @This();

// in the Logiverse, NetTableEntries, or "nets" for short,
// are tied to their virtually-physical representations "pins"
// many pins may reference the same net
csim_net_id: usize,
is_gate_output: bool,
is_gate_input: bool,
csim_gate_id: usize,
/// whether or not the pin is linked to a net
is_connected: bool,
/// if true, net's created from or wired to this pin will have .is_input = true
is_primary: bool,
dependant_comps: ArrayList(usize),
comp_id: ?usize,
tex: *Texture,

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const root = @import("root");
const raylib = root.raylib;
const rlgl = root.rlgl;
const Color = raylib.Color;
const Texture = raylib.Texture;

const math = @import("root").math;
const Vec2 = math.Vec2;
const Rect = math.geo.Rect;

const Logiverse = @import("../logiverse.zig").Logiverse;

const _obj = @import("../obj.zig");
const Object = _obj.Object;
const ObjectVTable = _obj.ObjectVTable;
const ObjectHandle = _obj.ObjectHandle;
const NoOp = _obj.NoOp;

pub const PIN_WORLD_RADIUS: f32 = 5;
pub const PIN_TEX_PATH = "resources/pin.png";

const _dbg_print_ignore_props = [_][]const u8{
    "dependant_comps",
    "tex",
};

pub const v_table = ObjectVTable{
    .init = Self._init,
    .spawn = Self.spawn,
    .delete = Self.delete,
    .render = Self.render,
    .update = Self.update,
    .mouseDown = NoOp.mouseDown,
    .mouseUp = NoOp.mouseDown,
    .mouseMove = NoOp.mouseMove,
    .debugPrint = Self.debugPrint,
};

fn init(allocator: Allocator) Self {
    return Self{
        .csim_net_id = 0,
        .csim_gate_id = 0,
        .is_gate_input = false,
        .is_gate_output = false,
        .is_connected = false,
        .is_primary = false,
        .dependant_comps = ArrayList(usize).init(allocator),
        .comp_id = null,
        .tex = undefined,
    };
}

fn _init(handle: *ObjectHandle, allocator: Allocator) anyerror!Object {
    _ = handle;
    return Object{
        .pin = Self.init(allocator),
    };
}

fn update(handle: *ObjectHandle, frame_time: f32) !void {
    _ = frame_time;
    const obj = handle.getObject();
    var pin = &obj.pin;

    var csim = handle.world.csim;

    if (pin.is_connected) {
        // detect if connected net is newly freed
        if (csim.net_table.free_ids.contains(pin.csim_net_id)) {
            pin.csim_net_id = 0;
            pin.is_connected = false;
        }
    }

    if (!pin.is_connected) {
        const net_id = try handle.world.csim.addNet(pin.is_primary);
        pin.csim_net_id = net_id;
        pin.is_connected = true;
    }

    var net = csim.net_table.getPtr(pin.csim_net_id);

    // check if we need to update whether net is an input
    if (pin.is_primary and !net.is_input) {
        net.is_input = true;
    }

    // check if we need to update gate inputs/output
    if (pin.is_gate_input) {
        var gate = handle.world.csim.gate_table.getPtr(pin.csim_gate_id);
        // if gate already depends on net, something didn't get cleaned up properly
        if (!gate.dependsOn(pin.csim_net_id)) {
            try gate.inputs.append(pin.csim_net_id);
        }
    } else if (pin.is_gate_output) {
        var gate = handle.world.csim.gate_table.getPtr(pin.csim_gate_id);
        gate.output = pin.csim_net_id;
    }
}

fn render(handle: *ObjectHandle, frame_time: f32) !void {
    _ = frame_time;
    const obj = handle.getObject();
    var pin = &obj.pin;
    const has_net = pin.is_connected;
    const is_active = if (has_net) handle.world.csim.getNetValue(pin.csim_net_id) else false;
    const pin_tint = if (is_active) raylib.YELLOW else raylib.WHITE;
    const maybe_net = if (has_net) handle.world.csim.net_table.getPtr(pin.csim_net_id) else null;
    const world_pos = handle.position;
    // std.debug.print("rendering pin at ({d}, {d})\n", .{ world_pos.v[0], world_pos.v[1] });
    var cam = handle.world.cam;
    if (!cam.visible_rect.containsPoint(world_pos)) {
        return;
    }
    const screen_pos = cam.worldToScreen(world_pos);
    const radius = cam.curr_scale * PIN_WORLD_RADIUS;
    const k = cam.curr_scale * PIN_WORLD_RADIUS * 2;
    if (has_net and maybe_net.?.is_input) {
        raylib.DrawCircleV(screen_pos.toRaylibVector2(), radius, raylib.GREEN);
    }
    if (handle.id == handle.world.hover_handle_id) {
        raylib.DrawCircleV(screen_pos.toRaylibVector2(), radius, raylib.YELLOW);
    }
    var screen_points: [5]Vec2(f32) = undefined;
    inline for (0..5) |c_i| {
        screen_points[c_i] = root.gfx.RectTexCoords[c_i].subScalar(0.5).mulScalar(k);
    }
    if (pin.is_connected) {
        const net_color = try handle.world.get_net_color(pin.csim_net_id);
        raylib.DrawCircleV(screen_pos.toRaylibVector2(), radius + 2, net_color);
    }
    root.gfx.drawTexturePoly(
        pin.tex.*,
        screen_pos,
        screen_points[0..],
        @constCast(root.gfx.RectTexCoords[0..]),
        pin_tint,
    );

    if (has_net) {
        const net = maybe_net.?;
        var txtBuff: [8]u8 = undefined;
        const written = try root.util.bufPrintNull(&txtBuff, "{d}", .{net.id});
        const font_size = 2 * cam.curr_scale;
        root.gfx.drawTextCentered(written, screen_pos, font_size, 1, .center, raylib.DARKGRAY);
    }
}

fn spawn(handle: *ObjectHandle) !void {
    std.log.info("spawning pin at: ({d}, {d})", .{ handle.position.v[0], handle.position.v[1] });
    const obj = handle.getObject();
    var pin = &obj.pin;
    pin.tex = try handle.world.resource_manager.getTexture(PIN_TEX_PATH);
    const r_vec = Vec2(f32).fill(PIN_WORLD_RADIUS);
    handle.rel_bounds = Rect(f32).init(Vec2(f32).zero.sub(r_vec), r_vec.mulScalar(2));
    const net_id = try handle.world.csim.addNet(false);
    pin.csim_net_id = net_id;
    pin.is_connected = true;
}

fn delete(handle: *ObjectHandle) !void {
    var wire_store = handle.mgr.getStore(.wire);
    var still_connected = true;
    while (still_connected) {
        still_connected = false;
        var wire_iter = wire_store.idIterator();
        while (wire_iter.next()) |wire_id| {
            const wire_hdl = handle.mgr.getHandleByObjectId(.wire, wire_id);
            var wire = wire_hdl.getObject().wire;
            if (wire.p0 == handle.obj_id or wire.p1 == handle.obj_id) {
                try wire_hdl.delete();
                still_connected = true;
                break;
            }
        }
    }
}

fn debugPrint(handle: *ObjectHandle) !void {
    var obj = handle.getObject();
    var pin = &obj.pin;
    root.util.debugPrintObjectIgnoringFields(Self, pin, _dbg_print_ignore_props);
}
