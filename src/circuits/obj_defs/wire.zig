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

pub const PIN_TEX_PATH = "resources/pin.png";
const Logiverse = @import("../logiverse.zig").Logiverse;

const _obj = @import("../obj.zig");
const Object = _obj.Object;
const ObjectVTable = _obj.ObjectVTable;
const ObjectHandle = _obj.ObjectHandle;
const NoOp = _obj.NoOp;

pub const WIRE_WIDTH: f32 = 2.5;

// a Wire is render info for a wire, and serves as a handle to delete the association
pub const Wire = struct {
    p0: usize,
    p1: usize,
    marked_for_deletion: bool,

    const Self = @This();

    pub const v_table = ObjectVTable{
        .init = Self._init,
        .spawn = Self.spawn,
        .delete = Self.delete,
        .render = Self.render,
        .update = NoOp.update,
        .mouseDown = NoOp.mouseDown,
        .mouseUp = NoOp.mouseUp,
        .mouseMove = NoOp.mouseMove,
        .debugPrint = NoOp.debugPrint,
    };

    pub fn init() Self {
        return Self{
            .p0 = 0,
            .p1 = 0,
            .marked_for_deletion = false,
        };
    }

    pub fn _init(handle: *ObjectHandle, allocator: Allocator) anyerror!Object {
        _ = handle;
        _ = allocator;
        return Object{
            .wire = Self.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    fn render(handle: *ObjectHandle, frame_time: f32) !void {
        _ = frame_time;
        var obj = handle.getObject();
        var wire = &obj.wire;
        var p0_hdl = handle.mgr.getHandleByObjectId(.pin, wire.p0);
        var p1_hdl = handle.mgr.getHandleByObjectId(.pin, wire.p1);
        const pos0 = handle.world.cam.worldToScreen(p0_hdl.position);
        const pos1 = handle.world.cam.worldToScreen(p1_hdl.position);

        var pin0 = p0_hdl.getObject().pin;
        var net_value = handle.world.csim.getNetValue(pin0.csim_net_id);
        // pos0.debugPrint();
        // pos1.debugPrint();

        var color = if (net_value) raylib.YELLOW else raylib.GRAY;

        raylib.DrawLineEx(pos0.toRaylibVector2(), pos1.toRaylibVector2(), WIRE_WIDTH, color);
    }

    fn spawn(handle: *ObjectHandle) !void {
        _ = handle;
    }

    fn delete(handle: *ObjectHandle) !void {
        var obj = handle.getObject();
        var ex_wire = &obj.wire;
        if (ex_wire.marked_for_deletion) return;
        var first_pin_hdl = handle.mgr.getHandleByObjectId(.pin, ex_wire.p0);
        var exiled_net_id = first_pin_hdl.getObject().pin.csim_net_id;

        var wire_store = handle.getStore();

        // step 1: record info about all wires in the net
        var other_wire_list = ArrayList(Wire).init(handle.world.allocator);
        var other_wire_hdls = ArrayList(*ObjectHandle).init(handle.world.allocator);
        defer other_wire_list.deinit();
        defer other_wire_hdls.deinit();
        var wire_iter = wire_store.idIterator();
        var c: usize = 0;
        while (wire_iter.next()) |wire_id| {
            var wire_hdl = handle.mgr.getHandleByObjectId(.wire, wire_id);
            var wire = &wire_hdl.getObject().wire;
            var p0_hdl = handle.mgr.getHandleByObjectId(.pin, wire.p0);
            var pin0 = &p0_hdl.getObject().pin;
            var net_id = pin0.csim_net_id;
            if (net_id != exiled_net_id) continue;
            var pin1 = &handle.mgr.getHandleByObjectId(.pin, wire.p1).getObject().pin;
            pin0.is_connected = false;
            pin1.is_connected = false;
            if (wire_id != handle.obj_id) {
                wire.marked_for_deletion = true;
                try other_wire_hdls.append(wire_hdl);
                try other_wire_list.append(wire.*);
                c += 1;
            }
        }

        // step 2: remove net from csim
        try handle.world.csim.freeNet(exiled_net_id);

        // step 3: fix adjacency list for the two directly connected pins

        std.debug.print("temp deleting {} wires\n", .{other_wire_hdls.items.len});
        // step 3: delete all recorded wires except the wire being disposed already (recurse)
        for (other_wire_hdls.items) |wire_hdl| {
            try wire_hdl.delete();
        }

        // step 4: rewire
        for (other_wire_list.items) |wire| {
            try handle.world.wirePins(wire.p0, wire.p1);
        }

        std.debug.print("found {} wires in net {}\n", .{ c, exiled_net_id });
    }
};
