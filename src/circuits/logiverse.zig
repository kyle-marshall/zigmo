const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;
const TailQueue = std.TailQueue;
const AutoHashMap = std.AutoHashMap;
const AutoArrayHashMap = std.AutoArrayHashMap;

pub const raylib = @cImport(@cInclude("raylib.h"));
pub const rlgl = @cImport(@cInclude("rlgl.h"));
const Color = raylib.Color;
const Texture = raylib.Texture;

const root = @import("root");
const util = root.util;
const math = root.math;
const Vec2 = math.Vec2;
const Mat3 = math.Mat3;
const Rect = math.geo.Rect;
const ObjectStore = root.ObjectStore;

const circuit_simulator = @import("circuit_simulator.zig");
const CircuitSimulator = circuit_simulator.CircuitSimulator;
const GateFactory = circuit_simulator.GateFactory;
const LogicValue = circuit_simulator.LogicValue;
const NetId = circuit_simulator.NetId;
const GateId = circuit_simulator.GateId;
const NetTableEntry = circuit_simulator.NetTableEntry;
const GateTableEntry = circuit_simulator.GateTableEntry;
const SimulateGateFn = circuit_simulator.SimulateGateFn;

const _obj = @import("obj.zig");
const ObjectHandle = _obj.ObjectHandle;
const ObjectVariant = _obj.ObjectVariant;
const ObjectFnTable = _obj.ObjectFnTable;
const NoopObjFns = _obj.NoopObjFns;

const Pin = @import("obj_defs/pin.zig").Pin;

// const LineSegment = struct {
//     a: Vec2(f32),
//     b: Vec2(f32),
// };
const MouseButton = enum { left, right, middle };

const ColoredLineSegment = struct {
    a: Vec2(f32),
    b: Vec2(f32),
    color: Color,
};

const geo = @import("root").geo;
const RadiusQueryResultItem = geo.RadiusQueryResultItem;
const PointData = geo.PointData;

const Cam2 = @import("root").cam.Cam2;

const gfx = @import("root").gfx;

const PIN_WORLD_RADIUS: f32 = 5;

const RectTexCoords = [5]Vec2(f32){
    Vec2(f32).init(0, 0),
    Vec2(f32).init(0, 1),
    Vec2(f32).init(1, 1),
    Vec2(f32).init(1, 0),
    Vec2(f32).init(0, 0),
};

const WIRE_WIDTH: f32 = 2.5;

const BW_WIDTH = 1000;
const BW_HEIGHT = 1000;
const BW_ORIGIN_X = BW_WIDTH / 2;
const BW_ORIGIN_Y = BW_HEIGHT / 2;
const BW_MAX_OBJECTS = 1_000_000;
const BW_MAX_INITIAL_SPEED = 50.0; // world units per second
const BW_INSTA_SPAWN_BATCH_SIZE = 10;

const PIN_TEX_PATH = "resources/pin.png";

const VOID_COLOR = Color{ .r = 20, .g = 49, .b = 65, .a = 255 };
const GRID_BG_COLOR = Color{ .r = 65, .g = 94, .b = 120, .a = 255 };
const MINOR_GRID_LINE_COLOR = Color{ .r = 63, .g = 108, .b = 155, .a = 255 };
const MAJOR_GRID_LINE_COLOR = Color{ .r = 90, .g = 135, .b = 169, .a = 255 };

const ResourceManager = struct {
    const Self = @This();
    textures: StringHashMap(Texture),
    pub fn init(allocator: Allocator) Self {
        return Self{
            .textures = StringHashMap(Texture).init(allocator),
        };
    }
    fn loadTexture(self: *Self, path: anytype) !void {
        var tex = raylib.LoadTexture(path);
        try self.textures.put(path, tex);
    }
    fn getTexture(self: *Self, path: []const u8) !Texture {
        const maybe_entry = self.textures.getEntry(path);
        const entry = maybe_entry.?;
        return entry.value_ptr.*;
    }
};

const CompId = usize;
const WorldGate = struct {
    comp_id: CompId,
    gate_id: GateId,
    /// owned pins will move with the component when it is moved
    owned_pins: ArrayList(usize),
    position: Vec2(f32),
    rect: Rect(f32),
    color: Color,

    const Self = @This();
    pub fn init(allocator: Allocator, comp_id: CompId, gate_id: GateId, position: Vec2(f32), rect: Rect(f32), color: Color) Self {
        return Self{
            .comp_id = comp_id,
            .gate_id = gate_id,
            .position = position,
            .rect = rect,
            .owned_pins = ArrayList(usize).init(allocator),
            .color = color,
        };
    }
};

const BlueprintId = usize;
const GateBlueprint = struct {
    id: BlueprintId,
    rect: Rect(f32),
    color: Color,
    input_positions: ArrayList(Vec2(f32)),
    output_position: Vec2(f32),
    simulate_fn: SimulateGateFn,
};

const BlueprintFactory = struct {
    const Self = @This();
    pub fn gate(allocator: Allocator, num_inputs: u32, gate_fn: SimulateGateFn) !GateBlueprint {
        var h: f32 = 40;
        var blueprint = GateBlueprint{
            .id = 0,
            .rect = Rect(f32).init(Vec2(f32).zero, Vec2(f32).init(30, h)),
            .input_positions = ArrayList(Vec2(f32)).init(allocator),
            .output_position = Vec2(f32).init(25, 20),
            .color = raylib.LIGHTGRAY,
            .simulate_fn = gate_fn,
        };
        const step: f32 = h / @intToFloat(f32, num_inputs + 1);
        for (0..num_inputs) |i| {
            try blueprint.input_positions.append(Vec2(f32).init(7.5, step * @intToFloat(f32, i + 1)));
        }
        return blueprint;
    }
    pub fn and2(allocator: Allocator) !GateBlueprint {
        return try Self.gate(allocator, 2, GateFactory.AND);
    }
};

// const BlueprintBelt = struct {
//     const Self = @This();
//     pub fn init(allocator: Allocator) Self {
//         return Self{};
//     }
//     pub fn deinit(self: *Self) void {}
// };

const LogiverseEvent = struct {
    net_id: usize,
    value: LogicValue,
};

pub const Logiverse = struct {
    const Self = @This();
    const SpatialHash = geo.spatial_hash.SpatialHash(f32, usize);

    // circuit fun
    csim: CircuitSimulator,

    // world state
    world_size: Vec2(f32),
    bounds: Rect(f32),

    handles: ObjectStore(ObjectHandle),
    obj_fns: [3]ObjectFnTable,

    pins: ObjectStore(Pin),
    components: ObjectStore(WorldGate),

    // world action state
    is_wiring: bool,
    wire_start_pin: usize,

    // qt: QuadTree,
    spatial_hash: SpatialHash,

    // view state
    screen_size: Vec2(f32),
    cam: Cam2(f32),
    mouse_pos: Vec2(f32),
    pan_start: Vec2(f32),
    is_panning: bool,

    hover_handle_id: ?usize,
    hover_pos: Vec2(f32),

    is_moving_obj: bool,
    moving_obj_tag: ObjectHandle,
    moving_obj_start_pos: Vec2(f32),

    // resources
    allocator: Allocator,
    resource_manager: ResourceManager,
    net_color: ArrayList(Color),
    rng: std.rand.Xoshiro256,

    pub fn init(allocator: Allocator, world_size: Vec2(f32), screen_size: Vec2(f32)) !Self {
        const bounds = Rect(f32).init(Vec2(f32).zero, world_size);
        var obj = Self{
            .allocator = allocator,
            .csim = try CircuitSimulator.init(allocator),
            .world_size = world_size,
            .screen_size = screen_size,
            .bounds = Rect(f32).init(Vec2(f32).zero, world_size),
            .cam = Cam2(f32).init(screen_size, Mat3(f32).identity),
            .spatial_hash = try SpatialHash.init(
                allocator,
                bounds,
                100.0,
            ),
            .resource_manager = ResourceManager.init(allocator),
            .pins = ObjectStore(Pin).init(allocator),
            .components = ObjectStore(WorldGate).init(allocator),
            .handles = ObjectStore(ObjectHandle).init(allocator),
            .pan_start = Vec2(f32).zero,
            .mouse_pos = Vec2(f32).zero,
            .is_panning = false,
            .is_wiring = false,
            .wire_start_pin = 0,
            .net_color = ArrayList(Color).init(allocator),
            .rng = undefined,
            .hover_handle_id = null,
            .hover_pos = Vec2(f32).zero,
            .is_moving_obj = false,
            .moving_obj_tag = undefined,
            .moving_obj_start_pos = Vec2(f32).zero,
            .obj_fns = undefined,
        };

        try obj.resource_manager.loadTexture(PIN_TEX_PATH);

        obj.cam.centerOnInstant(Vec2(f32).init(0, 0));

        obj.initObjFns();
        // add 10 input pins for testing
        for (0..10) |i| {
            // const pin_id = try obj.spawnPin(Vec2(f32).init(20, (@intToFloat(f32, i) + 1) * 20), true);
            const net_id = try obj.csim.addNet(true);
            const world_pos = Vec2(f32).init(20, (@intToFloat(f32, i) + 1) * 20);
            const handle = try obj.spawnObject(.pin, world_pos);
            const pin_id = handle.obj_id;
            var pin = obj.pins.getPtr(pin_id);
            pin.is_primary = true;
            pin.is_connected = true;
            pin.net_id = net_id;
        }

        const random_seed = std.crypto.random.int(u64);
        obj.rng = std.rand.Xoshiro256.init(random_seed);

        return obj;
    }

    fn initObjFns(self: *Self) void {
        self.obj_fns[@enumToInt(ObjectVariant.pin)] = Pin.obj_fn_table;
        self.obj_fns[@enumToInt(ObjectVariant.wire)] = ObjectFnTable{
            .spawn = NoopObjFns.spawn,
            .delete = NoopObjFns.delete,
            .update = NoopObjFns.update,
            .render = NoopObjFns.render,
        };
        self.obj_fns[@enumToInt(ObjectVariant.component)] = ObjectFnTable{
            .spawn = NoopObjFns.spawn,
            .delete = NoopObjFns.delete,
            .update = NoopObjFns.update,
            .render = NoopObjFns.render,
        };
    }

    pub inline fn getHandle(self: *Self, handle_id: usize) *ObjectHandle {
        return self.handles.getPtr(handle_id);
    }

    pub fn get_net_color(self: *Self, net_id: NetId) !Color {
        while (net_id >= self.net_color.items.len) {
            try self.net_color.append(Color{
                .r = @mod(self.rng.random().int(u8), 200) + 55,
                .g = @mod(self.rng.random().int(u8), 200) + 55,
                .b = @mod(self.rng.random().int(u8), 200) + 55,
                .a = 100,
            });
        }
        return self.net_color.items[net_id];
    }

    pub fn deinit(self: *Self) void {
        self.csim.deinit();
    }

    pub fn spawnObject(self: *Self, variant: ObjectVariant, world_pos: Vec2(f32)) !*ObjectHandle {
        const h_id = try self.handles.store(ObjectHandle{
            .id = 0,
            .variant = variant,
            .obj_id = 0,
            .position = world_pos,
            .rel_bounds = Rect(f32).init(Vec2(f32).zero, Vec2(f32).init(1, 1)),
        });
        var handle = self.getHandle(h_id);
        const fn_table = self.obj_fns[@enumToInt(handle.variant)];
        const obj_id = try fn_table.spawn(self, handle);
        handle.obj_id = obj_id;
        handle.id = h_id;
        _ = try self.spatial_hash.insert(world_pos, h_id);
        return handle;
    }

    pub fn removeObject(self: *Self, handle_id: usize) !void {
        _ = self.spatial_hash.remove(handle_id);
        var handle = self.getHandle(handle_id);
        const fn_table = self.obj_fns[@enumToInt(handle.variant)];
        try fn_table.delete(self, handle);
        try self.handles.remove(handle_id);
    }

    pub fn spawnComponentBlueprint(self: *Self, bp: *GateBlueprint, world_pos: Vec2(f32)) !void {
        const gate_id = self.csim.gate_table.items.len;

        try self.csim.gate_table.append(GateTableEntry{
            .id = gate_id,
            .inputs = ArrayList(NetId).init(self.allocator),
            .is_stale = true,
            .output = 0,
            .simulate = bp.simulate_fn,
        });

        var rect = bp.rect;
        _ = rect.origin.addInPlace(world_pos);
        const comp_id = try self.components.store(WorldGate.init(self.allocator, 0, gate_id, world_pos, rect, bp.color));
        var wgate = self.components.getPtr(comp_id);
        wgate.comp_id = comp_id;

        var gate = self.csim.gate_table.getPtr(gate_id);

        for (bp.input_positions.items) |in_pos| {
            const pos = world_pos.add(in_pos);
            const handle = self.spawnObject(.pin, pos);
            const pin_id = handle.obj_id;
            try wgate.owned_pins.append(pin_id);
            var pin = self.pins.getPtr(pin_id);
            const net_id = self.csim.addNet(false);
            pin.net_id = net_id;
            pin.comp_id = comp_id;
            var net = self.csim.net_table.getPtr(net_id);
            try net.fanout.append(gate_id);
            try gate.inputs.append(pin.net_id);
        }

        const pin_id = try self.spawnPin(world_pos.add(bp.output_position), true);
        gate.output = self.pins.items[pin_id].net_id;
        try wgate.owned_pins.append(pin_id);

        const tag_id = try self.spawnObject(.component, comp_id);
        _ = try self.spatial_hash.insert(world_pos, tag_id);
    }

    pub inline fn check_pin_adjacency(self: *Self, pin_a_id: usize, pin_b_id: usize) bool {
        var pin_a = self.pins.getPtr(pin_a_id);
        for (pin_a.adj_pins.items) |item| {
            if (item == pin_b_id) return true;
        }
        return false;
    }

    pub fn wirePins(self: *Self, p0: usize, p1: usize) !void {
        if (p0 == p1) {
            std.log.info("those are the same pins, you fool!", .{});
            return;
        }
        std.log.info("wire from {} to {}", .{ p0, p1 });
        if (self.check_pin_adjacency(p0, p1)) {
            std.log.info("pins are already wired. abort!", .{});
            return;
        }
        var pin0 = self.pins.getPtr(p0);
        var pin1 = self.pins.getPtr(p1);
        const any_primary = pin0.is_primary or pin1.is_primary;
        const n0 = pin0.net_id;
        const n1 = pin1.net_id;
        if (pin0.is_connected and pin1.is_connected) {
            // merge corresponding nets (no directionality preference... yet)
            try self.csim.mergeNets(n0, n1);
            std.debug.print("after merge:\n", .{});
            self.csim.printNetTable();
            var pinIter = self.pins.iterator();
            while (pinIter.next()) |pin| {
                const pin_id = pin.id;
                if (pin.net_id == n1) {
                    std.debug.print("p{} -> n{}\n", .{ pin_id, n0 });
                    pin.net_id = n0;
                }
                std.debug.print("p{} point to n{}\n", .{ pin_id, pin.net_id });
            }
        } else if (pin0.is_connected and !pin1.is_connected) {
            // pin_b joins pin_a's net
            pin1.net_id = pin0.net_id;
        } else if (pin1.is_connected and !pin0.is_connected) {
            // pin_a joins pin_b's net
            pin0.net_id = pin1.net_id;
        } else {
            // neither are connected, create a new net
            const net_id = try self.csim.addNet(false);
            pin0.net_id = net_id;
            pin1.net_id = net_id;
        }
        try pin0.adj_pins.append(p1);
        try pin1.adj_pins.append(p0);
        pin0.is_connected = true;
        pin1.is_connected = true;

        var net = self.csim.net_table.getPtr(pin0.net_id);

        if (any_primary) net.is_input = true;

        // trigger re-simulation
        if (net.is_input) net.is_undefined = true;

        self.csim.printNetTable();
        self.csim.printGateTable();
    }

    pub fn updateHoverObj(self: *Self) !void {
        const prev_hover_obj = self.hover_handle_id;
        self.hover_handle_id = null;
        const world_pos = self.cam.screenToWorld(self.mouse_pos);
        self.hover_pos = world_pos;
        if (!self.bounds.containsPoint(world_pos)) {
            return;
        }
        const results = try self.spatial_hash.query(self.allocator, world_pos, 50.0);
        for (results.items) |*item| {
            const h_id = item.point_data.data;
            const handle = self.getHandle(h_id);
            if (handle.variant == .pin and item.distance < PIN_WORLD_RADIUS) {
                self.hover_handle_id = h_id;
                break;
            }
            if (handle.variant == .component) {
                var component = self.components.getPtr(handle.obj_id);
                if (component.rect.containsPoint(world_pos)) {
                    self.hover_handle_id = h_id;
                    break;
                }
            }
        }
        if (self.hover_handle_id != prev_hover_obj) {
            std.debug.print("hover: {?}\n", .{self.hover_handle_id});
            if (self.hover_handle_id == null) return;
            var handle = self.getHandle(self.hover_handle_id.?);
            switch (handle.variant) {
                .component => {
                    // var component = self.components.getPtr(tag.index);
                    std.debug.print("hover component: {}\n", .{handle.obj_id});
                },
                .pin => {
                    var pin = self.pins.getPtr(handle.obj_id);
                    var net_id: ?usize = if (pin.is_connected) pin.net_id else null;
                    std.debug.print("hover pin: {} (net {?})\n", .{ handle.obj_id, net_id });
                },
                .wire => {
                    std.debug.print("hover wire: {}\n", .{handle.obj_id});
                },
            }
        }
    }

    pub fn _mouseButtonDown(self: *Self, button: MouseButton, screen_pos: Vec2(f32)) !void {
        if (button == .left) {
            if (self.hover_handle_id == null) {
                // _ = try self.spawnPin(self.hover_pos, false);
                _ = try self.spawnObject(.pin, self.hover_pos);
                // TODO place various stuff instead of just pins
                // const world_pos = self.cam.screenToWorld(screen_pos);
                // if (self.bounds.containsPoint(world_pos)) {
                //     var bp = try BlueprintFactory.and2(self.allocator);
                //     try self.spawnComponentBlueprint(&bp, world_pos);
                // }
                try self.updateHoverObj();
                return;
            }
            // action depends on what type of object we're hovering over
            const handle = self.getHandle(self.hover_handle_id.?);
            switch (handle.variant) {
                .component => {
                    std.log.info("clicked component {}", .{handle.obj_id});
                    // TODO start dragging component?
                },
                .pin => {
                    self.is_wiring = true;
                    self.wire_start_pin = handle.obj_id;
                    std.log.info("start wiring from pin {}...\n", .{handle.obj_id});
                },
                .wire => {
                    std.log.info("clicked wire {}", .{handle.obj_id});
                    // TODO start dragging wire?
                },
            }
        } else if (button == .right) {
            if (self.hover_handle_id == null) {
                std.log.info("right mouse down - noop", .{});
                return;
            }
            const handle = self.getHandle(self.hover_handle_id.?);
            switch (handle.variant) {
                .component => {
                    std.log.info("right clicked component {}", .{handle.obj_id});
                    // TODO delete component
                },
                .pin => {
                    std.log.info("right clicked pin {}", .{handle.obj_id});
                    try self.removeObject(handle.id);
                    try self.updateHoverObj();
                },
                .wire => {
                    std.log.info("right clicked wire {}", .{handle.obj_id});
                    // TODO delete wire
                },
            }
        } else {
            self.pan_start = screen_pos;
            self.is_panning = true;
            std.log.info("pan start", .{});
        }
    }

    pub fn _mouseButtonUp(self: *Self, button: MouseButton, screen_pos: Vec2(f32)) !void {
        _ = screen_pos;
        if (button == .left) {
            if (self.is_wiring) {
                const maybe_handle = if (self.hover_handle_id == null) null else self.getHandle(self.hover_handle_id.?);
                if (maybe_handle == null or maybe_handle.?.variant != .pin) {
                    std.log.info("cancel wire", .{});
                } else {
                    try self.wirePins(self.wire_start_pin, maybe_handle.?.obj_id);
                }
                self.is_wiring = false;
            }
        } else if (button == .right) {
            std.log.info("right mouse up - noop", .{});
        } else {
            self.is_panning = false;
            std.log.info("pan end", .{});
        }
    }

    pub fn _mouseMove(self: *Self, screen_pos: Vec2(f32)) !void {
        self.mouse_pos = screen_pos;
        // std.log.info("mouse move: ({d}, {d})", .{ screen_pos.v[0], screen_pos.v[1] });
        if (self.is_panning) {
            const delta = screen_pos.sub(self.pan_start);
            self.cam.applyTransform(Mat3(f32).txTranslate(delta.v[0], delta.v[1]));
            self.pan_start = screen_pos;
            return;
        }
        // update hover_obj
        try self.updateHoverObj();
    }

    pub fn _update(self: *Self, dt: f32) !void {
        // const num_keys = [_]c_int{
        //     raylib.KEY_ONE,
        //     raylib.KEY_TWO,
        //     raylib.KEY_THREE,
        //     raylib.KEY_FOUR,
        //     raylib.KEY_FIVE,
        //     raylib.KEY_SIX,
        //     raylib.KEY_SEVEN,
        //     raylib.KEY_EIGHT,
        // };
        // for (num_keys, 0..) |num_key, idx| {
        //     if (raylib.IsKeyPressed(num_key)) {
        //         const net_id = self.csim.external_inputs.items[idx];
        //         var net = self.csim.net_table.getPtr(net_id);
        //         const prev = net.external_signal;
        //         net.external_signal = !prev;
        //     }
        // }

        if (raylib.IsKeyPressed(raylib.KEY_Z)) {
            std.debug.print("\n", .{});
            self.csim.printNetTable();
        }
        _ = dt;
        try self.csim.simulate();
    }

    pub fn _draw(self: *Self) !void {
        // COMPONENT RECTS
        var compIter = self.components.iterator();
        while (compIter.next()) |comp| {
            const topLeft = self.cam.worldToScreen(comp.rect.origin);
            const botRight = self.cam.worldToScreen(comp.rect.origin.add(comp.rect.size));
            const size = botRight.sub(topLeft);
            raylib.DrawRectangleV(topLeft.toRaylibVector2(), size.toRaylibVector2(), comp.color);
        }
        // PINS
        var k = self.cam.curr_scale * PIN_WORLD_RADIUS * 2;
        var screen_points: [5]Vec2(f32) = undefined;
        var pin_tex = try self.resource_manager.getTexture(PIN_TEX_PATH);
        var wire_start_world_pos = Vec2(f32).zero;
        inline for (0..5) |c_i| {
            screen_points[c_i] = RectTexCoords[c_i].subScalar(0.5).mulScalar(k);
        }
        var wires_to_draw = ArrayList(ColoredLineSegment).init(self.allocator);
        defer wires_to_draw.deinit();
        var pinIter = self.pins.iterator();
        var t: usize = 0;
        while (pinIter.next()) |pin| {
            t += 1;
            const pin_id = pin.id;
            const is_active = if (!pin.is_connected) false else self.csim.getValue(pin.net_id);
            const pin_tint = if (is_active) raylib.YELLOW else raylib.WHITE;
            const wire_color = if (is_active) raylib.YELLOW else raylib.GRAY;
            const net_color = try self.get_net_color(pin.net_id);
            var net = self.csim.net_table.getPtr(pin.net_id);
            const world_pos = pin.position;
            if (pin_id == self.wire_start_pin) {
                wire_start_world_pos = world_pos;
            }
            if (!self.cam.visible_rect.containsPoint(world_pos)) {
                continue;
            }
            const screen_pos = self.cam.worldToScreen(world_pos);
            if (pin.is_connected and net.is_input) {
                raylib.DrawCircleV(screen_pos.toRaylibVector2(), k * 0.5, raylib.GREEN);
            }
            if (pin_id == self.hover_handle_id) {
                raylib.DrawCircleV(screen_pos.toRaylibVector2(), k * 0.75, raylib.YELLOW);
            }
            if (pin.is_connected) raylib.DrawCircleV(screen_pos.toRaylibVector2(), k * 0.75, net_color);
            gfx.drawTexturePoly(
                pin_tex,
                screen_pos,
                screen_points[0..],
                @constCast(RectTexCoords[0..]),
                pin_tint,
            );
            for (pin.adj_pins.items) |adj_pin_id| {
                if (adj_pin_id > pin_id) {
                    const other_pin = self.pins.getPtr(adj_pin_id);
                    try wires_to_draw.append(ColoredLineSegment{
                        .a = world_pos,
                        .b = other_pin.position,
                        .color = wire_color,
                    });
                }
            }
        }
        for (wires_to_draw.items) |line_seg| {
            const screen_a = self.cam.worldToScreen(line_seg.a).toRaylibVector2();
            const screen_b = self.cam.worldToScreen(line_seg.b).toRaylibVector2();
            raylib.DrawLineEx(screen_a, screen_b, WIRE_WIDTH, line_seg.color);
        }
        if (self.is_wiring) {
            const start = self.cam.worldToScreen(wire_start_world_pos);
            raylib.DrawLineEx(start.toRaylibVector2(), self.mouse_pos.toRaylibVector2(), WIRE_WIDTH, raylib.ORANGE);
        }
    }
};

pub fn initiateCircuitSandbox() !void {
    const allocator = std.heap.c_allocator;
    const screen_width = 800;
    const screen_height = 600;
    const draw_grid_lines = true;
    const screen_size_f = Vec2(f32).init(@intToFloat(f32, screen_width), @intToFloat(f32, screen_height));

    const grid_div = 100;
    var pan_speed: f32 = 10;
    var zoom_speed: f32 = 1.1;

    raylib.InitWindow(screen_width, screen_height, "transform_test");
    raylib.SetWindowPosition(1920, 64);
    defer raylib.CloseWindow();

    var world = try Logiverse.init(
        allocator,
        Vec2(f32).init(BW_WIDTH, BW_HEIGHT),
        screen_size_f,
    );
    defer world.deinit();

    var cam = &(world.cam);

    raylib.SetTargetFPS(60);
    var slowest_update_ms: u64 = 0;
    var slowest_draw_ms: u64 = 0;

    var prev_is_left_mouse_down = false;
    var prev_is_right_mouse_down = false;
    var prev_is_middle_mouse_down = false;
    var prev_mouse_pos = Vec2(f32).zero;

    while (!raylib.WindowShouldClose()) {
        const frame_time = raylib.GetFrameTime();
        const is_left_mouse_down = raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_LEFT);
        const is_right_mouse_down = raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_RIGHT);
        const is_middle_mouse_down = raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_MIDDLE);
        const mouse_pos = Vec2(f32).fromRaylibVector2(raylib.GetMousePosition());

        switch (is_left_mouse_down) {
            true => if (!prev_is_left_mouse_down) try world._mouseButtonDown(.left, mouse_pos),
            false => if (prev_is_left_mouse_down) try world._mouseButtonUp(.left, mouse_pos),
        }
        switch (is_right_mouse_down) {
            true => if (!prev_is_right_mouse_down) try world._mouseButtonDown(.right, mouse_pos),
            false => if (prev_is_right_mouse_down) try world._mouseButtonUp(.right, mouse_pos),
        }
        switch (is_middle_mouse_down) {
            true => if (!prev_is_middle_mouse_down) try world._mouseButtonDown(.middle, mouse_pos),
            false => if (prev_is_middle_mouse_down) try world._mouseButtonUp(.middle, mouse_pos),
        }

        if (!mouse_pos.equals(prev_mouse_pos)) {
            try world._mouseMove(mouse_pos);
        }

        prev_is_left_mouse_down = is_left_mouse_down;
        prev_is_right_mouse_down = is_right_mouse_down;
        prev_is_middle_mouse_down = is_middle_mouse_down;
        prev_mouse_pos = mouse_pos;

        if (raylib.IsKeyDown(raylib.KEY_RIGHT)) {
            const tx = Mat3(f32).txTranslate(-pan_speed, 0);
            cam.applyTransform(tx);
        }
        if (raylib.IsKeyDown(raylib.KEY_LEFT)) {
            const tx = Mat3(f32).txTranslate(pan_speed, 0);
            cam.applyTransform(tx);
        }
        if (raylib.IsKeyDown(raylib.KEY_UP)) {
            const tx = Mat3(f32).txTranslate(0, pan_speed);
            cam.applyTransform(tx);
        }
        if (raylib.IsKeyDown(raylib.KEY_DOWN)) {
            const tx = Mat3(f32).txTranslate(0, -pan_speed);
            cam.applyTransform(tx);
        }
        const wheel_move = raylib.GetMouseWheelMove();
        if (wheel_move > 0) {
            const tx = Mat3(f32).txScale(zoom_speed, zoom_speed);
            cam.applyTransform(tx);
        } else if (wheel_move < 0) {
            const s = 1.0 / zoom_speed;
            const tx = Mat3(f32).txScale(s, s);
            cam.applyTransform(tx);
        }

        // Update circuit simulation
        {
            const t0 = std.time.milliTimestamp();
            try world._update(frame_time);
            const t1 = std.time.milliTimestamp();
            const dt = @intCast(u64, t1 - t0);
            if (dt > slowest_update_ms) {
                slowest_update_ms = dt;
                std.debug.print("Slowest Logiverse update: {d} ms\n", .{dt});
            }
        }

        // Draw
        {
            const t0 = std.time.milliTimestamp();
            raylib.BeginDrawing();
            raylib.ClearBackground(VOID_COLOR);

            // GRID LINES
            if (draw_grid_lines) {
                var grid_size = world.bounds.size.div(Vec2(f32).init(grid_div, grid_div));
                var origin = cam.worldToScreen(world.bounds.origin);
                var maxPoint = cam.worldToScreen(origin.add(world.bounds.size));
                var screenSize = maxPoint.sub(origin);
                raylib.DrawRectangleV(origin.toRaylibVector2(), screenSize.toRaylibVector2(), GRID_BG_COLOR);
                var world_x: f32 = 0;
                var c: u32 = 0;
                while (world_x <= world.bounds.size.v[0]) : ({
                    world_x += grid_size.v[0];
                    c += 1;
                }) {
                    const s0 = cam.worldToScreen(Vec2(f32).init(world_x, 0)).floatToInt(i32);
                    const s1 = cam.worldToScreen(Vec2(f32).init(world_x, world.bounds.size.v[1])).floatToInt(i32);
                    const color = if (c % 10 == 0) MAJOR_GRID_LINE_COLOR else MINOR_GRID_LINE_COLOR;
                    raylib.DrawLine(s0.v[0], s0.v[1], s1.v[0], s1.v[1], color);
                }
                var world_y: f32 = 0;
                c = 0;
                while (world_y <= world.bounds.size.v[1]) : ({
                    world_y += grid_size.v[1];
                    c += 1;
                }) {
                    const s0 = cam.worldToScreen(Vec2(f32).init(0, world_y)).floatToInt(i32);
                    const s1 = cam.worldToScreen(Vec2(f32).init(world.bounds.size.v[0], world_y)).floatToInt(i32);
                    const color = if (c % 10 == 0) MAJOR_GRID_LINE_COLOR else MINOR_GRID_LINE_COLOR;
                    raylib.DrawLine(s0.v[0], s0.v[1], s1.v[0], s1.v[1], color);
                }
            }

            try world._draw();

            raylib.DrawRectangle(0, 0, screen_width, 40, raylib.BLACK);
            raylib.DrawText("Welcome to the Logiverse", 120, 10, 20, raylib.GREEN);
            // const obj_count = world.bunnies.items.len;
            // const count_txt = try std.fmt.allocPrint(allocator, "{d}", .{obj_count});
            // defer allocator.free(count_txt);
            // const count_c_str = try util.makeNullTerminatedString(allocator, count_txt);
            // defer allocator.free(count_c_str);

            // raylib.DrawText(&count_c_str[0], 200, 10, 20, raylib.GREEN);
            raylib.DrawFPS(10, 10);

            raylib.EndDrawing();
            const t1 = std.time.milliTimestamp();
            const dt = @intCast(u64, t1 - t0);
            if (dt < slowest_draw_ms) {
                slowest_draw_ms = dt;
                std.debug.print("slowest draw time: {d} ms\n", .{dt});
            }
        }
    }
}
