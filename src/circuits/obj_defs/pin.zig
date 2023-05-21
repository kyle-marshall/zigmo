const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const root = @import("root");
pub const raylib = @cImport(@cInclude("raylib.h"));
pub const rlgl = @cImport(@cInclude("rlgl.h"));
const Color = raylib.Color;
const Texture = raylib.Texture;

const math = @import("root").math;
const Vec2 = math.Vec2;
const Rect = math.geo.Rect;

pub const PIN_TEX_PATH = "resources/pin.png";
const Logiverse = @import("../logiverse.zig").Logiverse;

const _obj = @import("../obj.zig");
const Object = _obj.Object;
const ObjectVTable = _obj.ObjectVTable;
const ObjectHandle = _obj.ObjectHandle;
const NoOp = _obj.NoOp;

const PIN_WORLD_RADIUS: f32 = 5;

// in the Logiverse, NetTableEntries, or "nets" for short,
// are tied to their virtually-physical representations "pins"
// many pins may reference the same net
pub const Pin = struct {
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

    const _dbg_print_ignore_props = [_][]const u8{
        "dependant_comps",
        "tex",
    };

    const Self = @This();

    pub const v_table = ObjectVTable{
        .init = Self._init,
        .spawn = Self.spawn,
        .delete = Self.delete,
        .render = Self.render,
        .update = NoOp.update,
        .mouseDown = NoOp.mouseDown,
        .mouseUp = NoOp.mouseDown,
        .mouseMove = NoOp.mouseMove,
        .debugPrint = Self.debugPrint,
    };

    pub fn init(allocator: Allocator) Self {
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

    pub fn _init(handle: *ObjectHandle, allocator: Allocator) anyerror!Object {
        _ = handle;
        return Object{
            .pin = Pin.init(allocator),
        };
    }

    fn render(handle: *ObjectHandle, frame_time: f32) !void {
        _ = frame_time;
        var obj = handle.getObject();
        var pin = &obj.pin;
        var has_net = pin.is_connected;
        const is_active = if (has_net) handle.world.csim.getNetValue(pin.csim_net_id) else false;
        const pin_tint = if (is_active) raylib.YELLOW else raylib.WHITE;
        const net_color = try handle.world.get_net_color(pin.csim_net_id);
        var maybe_net = if (has_net) handle.world.csim.net_table.getPtr(pin.csim_net_id) else null;
        const world_pos = handle.position;
        // std.debug.print("rendering pin at ({d}, {d})\n", .{ world_pos.v[0], world_pos.v[1] });
        var cam = handle.world.cam;
        if (!cam.visible_rect.containsPoint(world_pos)) {
            return;
        }
        const screen_pos = cam.worldToScreen(world_pos);
        var k = cam.curr_scale * PIN_WORLD_RADIUS * 2;
        if (has_net and maybe_net.?.is_input) {
            raylib.DrawCircleV(screen_pos.toRaylibVector2(), k * 0.5, raylib.GREEN);
        }
        if (handle.id == handle.world.hover_handle_id) {
            raylib.DrawCircleV(screen_pos.toRaylibVector2(), k * 0.75, raylib.YELLOW);
        }
        var screen_points: [5]Vec2(f32) = undefined;
        inline for (0..5) |c_i| {
            screen_points[c_i] = root.gfx.RectTexCoords[c_i].subScalar(0.5).mulScalar(k);
        }
        if (pin.is_connected) raylib.DrawCircleV(screen_pos.toRaylibVector2(), k * 0.75, net_color);
        root.gfx.drawTexturePoly(
            pin.tex.*,
            screen_pos,
            screen_points[0..],
            @constCast(root.gfx.RectTexCoords[0..]),
            pin_tint,
        );

        if (has_net) {
            var net = maybe_net.?;
            var txtBuff: [8]u8 = undefined;
            var written = try root.util.bufPrintNull(&txtBuff, "{d}/{d}", .{ pin.csim_net_id, net.id });
            var x = screen_pos.v[0];
            var y = screen_pos.v[1];
            raylib.DrawText(
                &written[0],
                @floatToInt(c_int, x),
                @floatToInt(c_int, y),
                12,
                raylib.PINK,
            );
        }
    }

    fn spawn(handle: *ObjectHandle) !void {
        std.log.info("spawning pin at: ({d}, {d})", .{ handle.position.v[0], handle.position.v[1] });
        var obj = handle.getObject();
        var pin = &obj.pin;
        pin.tex = try handle.world.resource_manager.getTexture(PIN_TEX_PATH);
        var r_vec = Vec2(f32).fill(PIN_WORLD_RADIUS);
        handle.rel_bounds = Rect(f32).init(Vec2(f32).zero.sub(r_vec), r_vec.mulScalar(2));
    }

    fn delete(handle: *ObjectHandle) !void {
        var wire_store = handle.mgr.getStore(.wire);
        var still_connected = true;
        while (still_connected) {
            still_connected = false;
            var wire_iter = wire_store.idIterator();
            while (wire_iter.next()) |wire_id| {
                var wire_hdl = handle.mgr.getHandleByObjectId(.wire, wire_id);
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
};
