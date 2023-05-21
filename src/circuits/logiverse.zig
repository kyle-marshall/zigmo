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
const GateVariant = circuit_simulator.GateVariant;
const SimulateGateFn = circuit_simulator.SimulateGateFn;

const _obj = @import("obj.zig");
const ObjectManager = _obj.ObjectManager;
const ObjectHandle = _obj.ObjectHandle;
const ObjectVariant = _obj.ObjectVariant;
const ObjectVTable = _obj.ObjectVTable;
const NoOp = _obj.NoOp;

const pin_mod = @import("obj_defs/pin.zig");
const Pin = pin_mod.Pin;

const wire_mod = @import("obj_defs/wire.zig");
const Wire = wire_mod.Wire;

pub const MouseButton = enum { left, right, middle };

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

const BW_WIDTH = 1000;
const BW_HEIGHT = 1000;
const BW_ORIGIN_X = BW_WIDTH / 2;
const BW_ORIGIN_Y = BW_HEIGHT / 2;
const BW_MAX_OBJECTS = 1_000_000;
const BW_MAX_INITIAL_SPEED = 50.0; // world units per second
const BW_INSTA_SPAWN_BATCH_SIZE = 10;

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
    pub fn loadTexture(self: *Self, path: anytype) !void {
        try self.textures.put(path, raylib.LoadTexture(path));
    }
    pub fn getTexture(self: *Self, path: []const u8) !*Texture {
        const maybe_entry = self.textures.getEntry(path);
        const entry = maybe_entry.?;
        return entry.value_ptr;
    }
};

const CompId = usize;

const BlueprintId = usize;
const GateBlueprint = struct {
    id: BlueprintId,
    variant: GateVariant,
    rect: Rect(f32),
    color: Color,
    input_positions: ArrayList(Vec2(f32)),
    output_position: Vec2(f32),
    simulate_fn: SimulateGateFn,
};

const BlueprintFactory = struct {
    const Self = @This();
    pub inline fn gateVariantToColor(variant: GateVariant) Color {
        switch (variant) {
            .AND => return raylib.RED,
            .OR => return raylib.GREEN,
            .NOT => return raylib.WHITE,
            .XOR => return raylib.BLACK,
            .NAND => return raylib.PURPLE,
            .NOR => return raylib.BLUE,
            .XNOR => return raylib.LIGHTGRAY,
        }
    }
    pub inline fn getDefaultNumInputs(variant: GateVariant) u32 {
        if (variant == GateVariant.NOT) {
            return 1;
        }
        return 2;
    }
    pub fn gate(allocator: Allocator, num_inputs: u32, comptime variant: GateVariant) !GateBlueprint {
        var h: f32 = 40;
        var rect_size = Vec2(f32).init(30, h);
        var origin = rect_size.mulScalar(-0.5);
        var blueprint = GateBlueprint{
            .id = 0,
            .variant = variant,
            .rect = Rect(f32).init(origin, Vec2(f32).init(30, h)),
            .input_positions = ArrayList(Vec2(f32)).init(allocator),
            .output_position = Vec2(f32).init(10, 0),
            .color = Self.gateVariantToColor(variant),
            .simulate_fn = GateFactory.getSimulateFn(variant),
        };
        const step: f32 = h / @intToFloat(f32, num_inputs + 1);
        for (0..num_inputs) |i| {
            try blueprint.input_positions.append(Vec2(f32).init(
                origin.v[0] + 5,
                origin.v[1] + step * @intToFloat(f32, i + 1),
            ));
        }
        blueprint.rect.debugPrint();
        return blueprint;
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

    obj_mgr: ObjectManager,

    // handles: ObjectStore(ObjectHandle),
    // obj_v_tables: [3]ObjectVTable,

    // pins: ObjectStore(Pin),
    // components: ObjectStore(WorldGate),

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
        const random_seed = std.crypto.random.int(u64);
        const bounds = Rect(f32).init(Vec2(f32).zero, world_size);
        return Self{
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
            .obj_mgr = try ObjectManager.init(allocator),
            // .pins = ObjectStore(Pin).init(allocator),
            // .components = ObjectStore(WorldGate).init(allocator),
            // .handles = ObjectStore(ObjectHandle).init(allocator),
            .pan_start = Vec2(f32).zero,
            .mouse_pos = Vec2(f32).zero,
            .is_panning = false,
            .is_wiring = false,
            .wire_start_pin = 0,
            .net_color = ArrayList(Color).init(allocator),
            .rng = std.rand.Xoshiro256.init(random_seed),
            .hover_handle_id = null,
            .hover_pos = Vec2(f32).zero,
            .is_moving_obj = false,
            .moving_obj_tag = undefined,
            .moving_obj_start_pos = Vec2(f32).zero,
        };
    }

    pub fn load_textures(self: *Self) !void {
        try self.resource_manager.loadTexture(pin_mod.PIN_TEX_PATH);
    }

    pub fn init_test_pins(self: *Self) !void {
        // add 10 input pins for testing
        for (0..10) |i| {
            // const pin_id = try obj.spawnPin(Vec2(f32).init(20, (@intToFloat(f32, i) + 1) * 20), true);
            const net_id = try self.csim.addNet(true);
            const world_pos = Vec2(f32).init(20, (@intToFloat(f32, i) + 1) * 20);
            const handle = try self.spawnObject(.pin, world_pos);
            var obj = handle.getObject();
            var pin = &obj.pin;
            pin.is_primary = true;
            pin.is_connected = true;
            pin.csim_net_id = net_id;
        }
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
        const handle = try self.obj_mgr.createHandle(variant);
        handle.world = self;
        handle.position = world_pos;
        try handle.spawn();
        _ = try self.spatial_hash.insert(world_pos, handle.id);
        std.debug.print("spawned object {} -> {} {}\n", .{ handle.id, handle.variant, handle.obj_id });
        return handle;
    }

    pub fn removeObject(self: *Self, handle_id: usize) !void {
        var handle = self.obj_mgr.getHandle(handle_id);
        if (handle.parent_id != null) {
            std.debug.print("can't remove an object that has a parent\n", .{});
            return;
        }
        try handle.delete();
    }

    pub fn spawnGate(self: *Self, bp: *GateBlueprint, world_pos: Vec2(f32)) !void {
        var input_net_ids = ArrayList(NetId).init(self.allocator);
        var spawned_pin_handle_ids = ArrayList(usize).init(self.allocator);
        defer input_net_ids.deinit();

        for (bp.input_positions.items) |in_pos| {
            const pos = world_pos.add(in_pos);
            const net_id = try self.csim.addNet(false);
            try input_net_ids.append(net_id);
            const pin_hdl = try self.spawnObject(.pin, pos);
            try spawned_pin_handle_ids.append(pin_hdl.id);
            var pin = &pin_hdl.getObject().pin;
            pin.is_connected = true;
            pin.csim_net_id = net_id;
        }

        const output_net_id = try self.csim.addNet(false);
        const output_pos = world_pos.add(bp.output_position);
        const output_handle = try self.spawnObject(.pin, output_pos);
        var output_obj = output_handle.getObject();
        var output_pin = &output_obj.pin;
        try spawned_pin_handle_ids.append(output_handle.id);
        output_pin.is_connected = true;
        output_pin.csim_net_id = output_net_id;

        const csim_gate_id = try self.csim.addGate(bp.simulate_fn, input_net_ids.items, output_net_id);

        var wgate_hdl = try self.spawnObject(.gate, world_pos);
        var wgate = &wgate_hdl.getObject().gate;
        wgate.variant = bp.variant;
        wgate.csim_gate_id = csim_gate_id;
        wgate.color = bp.color;
        wgate_hdl.rel_bounds = bp.rect;

        for (spawned_pin_handle_ids.items) |pin_hdl_id| {
            var pin_hdl = self.obj_mgr.getHandle(pin_hdl_id);
            pin_hdl.parent_id = wgate_hdl.id;
            try wgate.owned_pins.append(pin_hdl_id);
            var pin = &pin_hdl.getObject().pin;
            pin.csim_gate_id = csim_gate_id;
            if (pin_hdl.id == output_handle.id) {
                pin.is_gate_output = true;
            } else {
                pin.is_gate_input = true;
            }
        }
    }

    pub inline fn check_pin_adjacency(self: *Self, p0: usize, p1: usize) bool {
        var wire_store = self.obj_mgr.getStore(.wire);
        var wire_iter = wire_store.iterator();
        while (wire_iter.next()) |wire_obj| {
            var wire = &wire_obj.wire;
            if (wire.p0 == p0 and wire.p1 == p1) {
                return true;
            }
            if (wire.p0 == p1 and wire.p1 == p0) {
                return true;
            }
        }
        return false;
    }

    /// when pin is rewired we need to update the csim
    /// to link it with it's gates
    pub fn onPinRewired(self: *Self, pin_hdl: *ObjectHandle) !void {
        var pin = &pin_hdl.getObject().pin;
        std.debug.print("onPinRewired: pin {}/{}\n", .{ pin_hdl.id, pin_hdl.obj_id });
        var net = self.csim.net_table.getPtr(pin.csim_net_id);
        if (pin.is_gate_input) {
            // ensure net fanout includes gate id
            for (net.fanout.items) |gate_id| {
                if (gate_id == pin.csim_gate_id) {
                    std.debug.print("onPinRewired: net {} fanout already includes gate {}\n", .{ pin.csim_net_id, pin.csim_gate_id });
                    return;
                }
            }
            try net.fanout.append(pin.csim_gate_id);
            std.debug.print("onPinRewired: net {} fanout updated to {any}\n", .{ pin.csim_net_id, net.fanout.items });
        } else if (pin.is_gate_output) {
            var gate = self.csim.gate_table.getPtr(pin.csim_gate_id);
            // ensure gate output is set to net id
            if (gate.output == pin.csim_net_id) {
                std.debug.print("onPinRewired: gate {} output already set to {}\n", .{ pin.csim_gate_id, pin.csim_net_id });
                std.debug.print("{*}\n", .{gate});
                gate.debugPrint();
                return;
            }
            gate.output = pin.csim_net_id;
            std.debug.print("onPinRewired: gate {} output set to {}\n", .{ pin.csim_gate_id, pin.csim_net_id });
        } else {
            std.debug.print("onPinRewired: pin {} is not gate input or output\n", .{pin_hdl.id});
        }
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
        var pin0_hdl = self.obj_mgr.getHandleByObjectId(.pin, p0);
        var pin1_hdl = self.obj_mgr.getHandleByObjectId(.pin, p1);

        // TODO rewrite everything to use handles/handle_ids

        var pinStore = self.obj_mgr.getStore(.pin);
        var obj0 = pinStore.getPtr(p0);
        var pin0 = &obj0.pin;
        var obj1 = pinStore.getPtr(p1);
        var pin1 = &obj1.pin;
        const any_primary = pin0.is_primary or pin1.is_primary;
        const n0 = pin0.csim_net_id;
        const n1 = pin1.csim_net_id;
        if (pin0.is_connected and pin1.is_connected) {
            // merge corresponding nets (no directionality preference... yet)
            try self.csim.mergeNets(n0, n1);
            std.debug.print("after merge:\n", .{});
            self.csim.printNetTable();
            var pinIter = pinStore.idIterator();
            while (pinIter.next()) |obj_id| {
                var obj = pinStore.getPtr(obj_id);
                var pin = &obj.pin;
                if (pin.csim_net_id == n1) {
                    // std.debug.print("p{} -> n{}\n", .{ obj_id, n0 });
                    pin.csim_net_id = n0;
                }
                // std.debug.print("p{} point to n{}\n", .{ obj_id, pin.csim_net_id });
            }
        } else if (pin0.is_connected and !pin1.is_connected) {
            // pin_b joins pin_a's net
            pin1.csim_net_id = pin0.csim_net_id;
        } else if (pin1.is_connected and !pin0.is_connected) {
            // pin_a joins pin_b's net
            pin0.csim_net_id = pin1.csim_net_id;
        } else {
            // neither are connected, create a new net
            const net_id = try self.csim.addNet(false);
            pin0.csim_net_id = net_id;
            pin1.csim_net_id = net_id;
        }
        pin0.is_connected = true;
        pin1.is_connected = true;

        var net = self.csim.net_table.getPtr(pin0.csim_net_id);

        if (any_primary) net.is_input = true;
        // trigger re-simulation
        if (net.is_input) net.is_undefined = true;

        try self.onPinRewired(pin0_hdl);
        try self.onPinRewired(pin1_hdl);

        // self.csim.printNetTable();
        // self.csim.printGateTable();

        var handle = try self.spawnObject(.wire, Vec2(f32).zero);
        var obj = handle.getObject();
        var wire = &obj.wire;
        wire.p0 = p0;
        wire.p1 = p1;
    }

    pub fn updateHoverObj(self: *Self) !void {
        const prev_hover_obj = self.hover_handle_id;
        self.hover_handle_id = null;
        const world_pos = self.cam.screenToWorld(self.mouse_pos);
        self.hover_pos = world_pos;
        if (!self.bounds.containsPoint(world_pos)) {
            return;
        }
        const results = try self.spatial_hash.query(self.allocator, world_pos, 100.0);

        // first pass just look for a pin
        for (results.items) |*item| {
            const h_id = item.point_data.data;
            const handle = self.obj_mgr.getHandle(h_id);
            if (handle.variant != .pin) continue;
            const diff = item.point_data.point.sub(world_pos);
            if (handle.rel_bounds.containsPoint(diff)) {
                self.hover_handle_id = h_id;
                break;
            }
        }
        if (self.hover_handle_id == null) {
            // second pass, match anything else
            for (results.items) |*item| {
                const h_id = item.point_data.data;
                const handle = self.obj_mgr.getHandle(h_id);
                if (handle.variant == .pin) continue;
                const diff = item.point_data.point.sub(world_pos);
                if (handle.rel_bounds.containsPoint(diff)) {
                    self.hover_handle_id = h_id;
                    break;
                }
            }
        }
        if (self.hover_handle_id != prev_hover_obj) {
            std.debug.print("hover_handle_id <- {?}\n", .{self.hover_handle_id});
            if (self.hover_handle_id == null) return;
            var handle = self.obj_mgr.getHandle(self.hover_handle_id.?);
            try handle.debugPrint();
        }
    }

    pub fn _mouseButtonDown(self: *Self, button: MouseButton, screen_pos: Vec2(f32)) !void {
        if (button == .left) {
            if (self.hover_handle_id == null) {
                // _ = try self.spawnPin(self.hover_pos, false);

                if (raylib.IsKeyDown(raylib.KEY_ONE)) {
                    // and gate
                    var bp = try BlueprintFactory.gate(self.allocator, 2, .AND);
                    try self.spawnGate(&bp, self.hover_pos);
                } else if (raylib.IsKeyDown(raylib.KEY_TWO)) {
                    // or gate
                    var bp = try BlueprintFactory.gate(self.allocator, 2, .OR);
                    try self.spawnGate(&bp, self.hover_pos);
                } else if (raylib.IsKeyDown(raylib.KEY_THREE)) {
                    // nand gate
                    var bp = try BlueprintFactory.gate(self.allocator, 2, .NAND);
                    try self.spawnGate(&bp, self.hover_pos);
                } else if (raylib.IsKeyDown(raylib.KEY_Q)) {
                    _ = try self.spawnObject(.source, self.hover_pos);
                } else {
                    _ = try self.spawnObject(.pin, self.hover_pos);
                }
                try self.updateHoverObj();
                return;
            }
            // action depends on what type of object we're hovering over
            const handle = self.obj_mgr.getHandle(self.hover_handle_id.?);
            switch (handle.variant) {
                .pin => {
                    self.is_wiring = true;
                    self.wire_start_pin = handle.obj_id;
                    std.log.info("start wiring from pin {}...\n", .{handle.obj_id});
                },
                else => {
                    try handle.mouseDown(.left, self.hover_pos);
                },
            }
        } else if (button == .right) {
            if (self.hover_handle_id == null) {
                std.log.info("right mouse down - noop", .{});
                return;
            }
            const handle = self.obj_mgr.getHandle(self.hover_handle_id.?);
            try self.removeObject(handle.id);
            try self.updateHoverObj();
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
                const maybe_handle = if (self.hover_handle_id == null) null else self.obj_mgr.getHandle(self.hover_handle_id.?);
                if (maybe_handle == null or maybe_handle.?.variant != .pin) {
                    std.log.info("cancel wire", .{});
                } else {
                    try self.wirePins(self.wire_start_pin, maybe_handle.?.obj_id);
                }
                self.is_wiring = false;
                return;
            }
        } else if (button == .right) {
            std.log.info("right mouse up - noop", .{});
        } else {
            self.is_panning = false;
            std.log.info("pan end", .{});
        }

        if (self.hover_handle_id == null) {
            return;
        }
        // action depends on what type of object we're hovering over
        const handle = self.obj_mgr.getHandle(self.hover_handle_id.?);
        try handle.mouseUp(.left, self.hover_pos);
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

    pub fn updateAllObjectsOfVariant(self: *Self, variant: ObjectVariant, frame_time: f32) !void {
        var store = self.obj_mgr.getStore(variant);
        var iter = store.idIterator();
        while (iter.next()) |obj_id| {
            var handle = self.obj_mgr.getHandleByObjectId(variant, obj_id);
            try handle.update(frame_time);
        }
    }

    pub fn _update(self: *Self, dt: f32) !void {
        try self.updateAllObjectsOfVariant(.source, dt);

        if (raylib.IsKeyPressed(raylib.KEY_Z)) {
            std.debug.print("\n", .{});
            self.csim.printNetTable();
            self.csim.printGateTable();
        }
        try self.csim.simulate();
    }

    pub fn drawAllObjectsOfVariant(self: *Self, variant: ObjectVariant, frame_time: f32) !void {
        var store = self.obj_mgr.getStore(variant);
        var iter = store.idIterator();
        var c: usize = 0;
        while (iter.next()) |obj_id| {
            var handle = self.obj_mgr.getHandleByObjectId(variant, obj_id);
            try handle.render(frame_time);
            c += 1;
        }
        // std.log.info("drawAllObjectsOfVariant: {} objects", .{c});
    }

    pub fn _draw(self: *Self, frame_time: f32) !void {
        try self.drawAllObjectsOfVariant(.gate, frame_time);
        try self.drawAllObjectsOfVariant(.source, frame_time);
        try self.drawAllObjectsOfVariant(.pin, frame_time);
        try self.drawAllObjectsOfVariant(.wire, frame_time);

        if (self.is_wiring) {
            var start_pin_handle = self.obj_mgr.getHandleByObjectId(.pin, self.wire_start_pin);
            const start = self.cam.worldToScreen(start_pin_handle.position);
            raylib.DrawLineEx(start.toRaylibVector2(), self.mouse_pos.toRaylibVector2(), wire_mod.WIRE_WIDTH, raylib.ORANGE);
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
    try world.load_textures();
    // try world.init_test_pins();

    var cam = &(world.cam);
    cam.centerOnInstant(Vec2(f32).init(200, 150));

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
                const screen_rect = world.cam.worldToScreenRect(world.bounds);
                raylib.DrawRectangleV(screen_rect.origin.toRaylibVector2(), screen_rect.size.toRaylibVector2(), GRID_BG_COLOR);
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

            try world._draw(frame_time);

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
