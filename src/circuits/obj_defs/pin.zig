const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const math = @import("root").math;
const Vec2 = math.Vec2;
const Logiverse = @import("../logiverse.zig").Logiverse;

const _obj = @import("../obj.zig");
const ObjectFnTable = _obj.ObjectFnTable;
const ObjectHandle = _obj.ObjectHandle;
const NoopObjFns = _obj.NoopObjFns;

// in the Logiverse, NetTableEntries, or "nets" for short,
// are tied to their virtually-physical representations "pins"
// many pins may reference the same net
pub const Pin = struct {
    id: usize,
    net_id: usize,
    /// whether or not the pin is linked to a net
    is_connected: bool,
    /// if true, net's created from or wired to this pin will have .is_input = true
    is_primary: bool,
    position: Vec2(f32),
    adj_pins: ArrayList(usize),
    dependant_comps: ArrayList(usize),
    comp_id: ?usize,

    pub const obj_fn_table = ObjectFnTable{
        .spawn = Pin._spawn,
        .delete = Pin._delete,
        .render = NoopObjFns.render,
        .update = NoopObjFns.update,
    };

    pub fn init(allocator: Allocator, position: Vec2(f32)) Pin {
        return Pin{
            .id = 0,
            .net_id = 0,
            .is_connected = false,
            .is_primary = false,
            .position = position,
            .adj_pins = ArrayList(usize).init(allocator),
            .dependant_comps = ArrayList(usize).init(allocator),
            .comp_id = null,
        };
    }

    pub fn deinit(self: *Pin) void {
        self.adj_pins.deinit();
    }

    fn _spawn(world: *Logiverse, handle: *ObjectHandle) !usize {
        std.log.info("spawning pin at: ({d}, {d})", .{ handle.position.v[0], handle.position.v[1] });
        const pin_id = try world.pins.store(Pin.init(world.allocator, handle.position));
        const pin = world.pins.getPtr(pin_id);
        pin.id = pin_id;
        return pin_id;
    }

    fn _delete(world: *Logiverse, handle: *ObjectHandle) !void {
        const pin_id = handle.obj_id;
        std.debug.print("removePin {}\n", .{pin_id});

        var exiled_pin = world.pins.getPtr(pin_id);
        defer exiled_pin.deinit();

        if (exiled_pin.comp_id == null and !exiled_pin.is_connected) {
            // special case, simply remove the pin
            std.debug.print("special case, simply remove the pin\n", .{});
            try world.pins.remove(pin_id);
            return;
        }

        var exiled_net_id = exiled_pin.net_id;

        // step 1: record info about all wires in pin's net
        var wire_list = ArrayList(Vec2(usize)).init(world.allocator);
        defer wire_list.deinit();
        var pinIter = world.pins.iterator();
        var c: usize = 0;
        while (pinIter.next()) |pin0| {
            const p0 = pin0.id;
            if (pin0.net_id != exiled_net_id) continue;
            pin0.is_connected = false;
            for (pin0.adj_pins.items) |p1| {
                // avoid counting each edge twice
                if (p1 > p0) {
                    try wire_list.append(Vec2(usize).init(p0, p1));
                }
            }
            c += 1;
        }
        std.debug.print("found {} pins in net {}\n", .{ c, exiled_net_id });

        // step 2: remove net from csim
        try world.csim.freeNet(exiled_net_id);

        // step 3: all wires we recorded info about, then remove exiled_pin
        for (wire_list.items) |wire| {
            const p0 = wire.v[0];
            const p1 = wire.v[1];
            var pin0 = world.pins.getPtr(p0);
            var pin1 = world.pins.getPtr(p1);
            for (pin0.adj_pins.items, 0..) |adj_id, idx| {
                if (adj_id == p1) {
                    _ = pin0.adj_pins.swapRemove(idx);
                    break;
                }
            }
            for (pin1.adj_pins.items, 0..) |adj_id, idx| {
                if (adj_id == p0) {
                    _ = pin1.adj_pins.swapRemove(idx);
                    break;
                }
            }
        }
        try world.pins.remove(pin_id);

        // step 4: re-wire all wires which did not connect to pin
        for (wire_list.items) |wire| {
            if (wire.v[0] == exiled_pin.id or wire.v[1] == exiled_pin.id) continue;
            try world.wirePins(wire.v[0], wire.v[1]);
        }
    }
};
