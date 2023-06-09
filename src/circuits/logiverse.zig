const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;
const TailQueue = std.TailQueue;
const AutoHashMap = std.AutoHashMap;
const AutoArrayHashMap = std.AutoArrayHashMap;

const raylib = @cImport(@cInclude("raylib.h"));
const rlgl = @cImport(@cInclude("rlgl.h"));
const Color = raylib.Color;
const Texture = raylib.Texture;

const root = @import("root");
const util = root.util;
const math = root.math;
const Vec2 = math.Vec2;
const Mat3 = math.Mat3;
const Rect = math.geo.Rect;
const ObjectStore = root.ObjectStore;
const Cam2 = root.cam.Cam2;
const Cam2Controller = root.cam.Cam2Controller;
const gfx = root.gfx;

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

const Pin = @import("obj_defs/Pin.zig");
const Wire = @import("obj_defs/Wire.zig");
const Gate = @import("obj_defs/Gate.zig");

pub const MouseButton = enum { left, right, middle };

const ColoredLineSegment = struct {
    a: Vec2(f32),
    b: Vec2(f32),
    color: Color,
};

const geo = @import("root").geo;
const RadiusQueryResultItem = geo.RadiusQueryResultItem;
const PointData = geo.PointData;

const BW_WIDTH = 1024;
const BW_HEIGHT = 1024;
const BW_ORIGIN_X = BW_WIDTH / 2;
const BW_ORIGIN_Y = BW_HEIGHT / 2;
const BW_MAX_OBJECTS = 1_000_000;
const BW_MAX_INITIAL_SPEED = 50.0; // world units per second
const BW_INSTA_SPAWN_BATCH_SIZE = 10;

const VOID_COLOR = Color{ .r = 20, .g = 49, .b = 65, .a = 255 };

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
    name: []const u8,
    num_inputs: u32,
    variant: GateVariant,
    simulate_fn: SimulateGateFn,

    const Self = @This();
    pub fn init(name: []const u8, num_inputs: u32, comptime variant: GateVariant) Self {
        return Self{
            .name = name,
            .num_inputs = num_inputs,
            .variant = variant,
            .simulate_fn = GateFactory.getSimulateFn(variant),
        };
    }
};

const GATE_BLUEPRINTS = [_]GateBlueprint{
    GateBlueprint.init("AND", 2, GateVariant.AND),
    GateBlueprint.init("OR", 2, GateVariant.OR),
    GateBlueprint.init("NOT", 1, GateVariant.NOT),
    GateBlueprint.init("XOR", 2, GateVariant.XOR),
    GateBlueprint.init("NAND", 2, GateVariant.NAND),
    GateBlueprint.init("NOR", 2, GateVariant.NOR),
    GateBlueprint.init("XNOR", 2, GateVariant.XNOR),
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

    // world action state
    is_wiring: bool,
    wire_start_pin: usize,

    // qt: QuadTree,
    spatial_hash: SpatialHash,

    // view state
    screen_size: Vec2(f32),
    cam: Cam2(f32),
    mouse_pos: Vec2(f32),

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
            .mouse_pos = Vec2(f32).zero,
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
        try self.resource_manager.loadTexture(Pin.PIN_TEX_PATH);
    }

    pub fn init_test_pins(self: *Self) !void {
        // add 10 input pins for testing
        for (0..10) |i| {
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
        std.log.info("spawned object {} -> {} {}\n", .{ handle.id, handle.variant, handle.obj_id });
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

        var height: f32 = @intToFloat(f32, bp.num_inputs) * 10;
        var width: f32 = 30;
        var size = Vec2(f32).init(width, height);
        var rel_bounds = Rect(f32).init(Vec2(f32).zero.sub(size.divScalar(2)), size);

        var input_stride = Vec2(f32).init(0, Pin.PIN_WORLD_RADIUS * 2);
        var in_pos = rel_bounds.origin.add(Vec2(f32).fill(Pin.PIN_WORLD_RADIUS));

        for (0..bp.num_inputs) |_| {
            const pos = world_pos.add(in_pos);
            const pin_hdl = try self.spawnObject(.pin, pos);
            try spawned_pin_handle_ids.append(pin_hdl.id);
            var pin = &pin_hdl.getObject().pin;
            try input_net_ids.append(pin.csim_net_id);
            in_pos = in_pos.add(input_stride);
        }

        const output_pos = world_pos.add(Vec2(f32).X.mulScalar(width / 2 - Pin.PIN_WORLD_RADIUS));
        const output_handle = try self.spawnObject(.pin, output_pos);
        var output_obj = output_handle.getObject();
        var output_pin = &output_obj.pin;
        try spawned_pin_handle_ids.append(output_handle.id);

        const csim_gate_id = try self.csim.addGate(
            bp.simulate_fn,
            input_net_ids.items,
            output_pin.csim_net_id,
        );

        var wgate_hdl = try self.spawnObject(.gate, world_pos);
        var wgate = &wgate_hdl.getObject().gate;
        wgate.variant = bp.variant;
        wgate.csim_gate_id = csim_gate_id;
        wgate.color = Gate.gateVariantToColor(bp.variant);
        wgate_hdl.rel_bounds = rel_bounds;

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
        // var pin0_hdl = self.obj_mgr.getHandleByObjectId(.pin, p0);
        // var pin1_hdl = self.obj_mgr.getHandleByObjectId(.pin, p1);

        // TODO rewrite everything to use handles/handle_ids

        var pin_store = self.obj_mgr.getStore(.pin);
        var obj0 = pin_store.getPtr(p0);
        var pin0 = &obj0.pin;
        var obj1 = pin_store.getPtr(p1);
        var pin1 = &obj1.pin;
        const any_primary = pin0.is_primary or pin1.is_primary;
        const n0 = pin0.csim_net_id;
        const n1 = pin1.csim_net_id;
        if (pin0.is_connected and pin1.is_connected) {
            // merge corresponding nets (no directionality preference... yet)
            try self.csim.mergeNets(n0, n1);
            std.debug.print("after merge:\n", .{});
            self.csim.debugPrintState();
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

        var pin_iter = pin_store.idIterator();
        while (pin_iter.next()) |obj_id| {
            var obj = pin_store.getPtr(obj_id);
            var pin = &obj.pin;
            if (pin.csim_net_id == n1) {
                pin.csim_net_id = n0;
            }
        }

        var net = self.csim.net_table.getPtr(pin0.csim_net_id);

        if (any_primary) net.is_input = true;
        // trigger re-simulation
        if (net.is_input) net.is_undefined = true;

        // try self.onPinRewired(pin0_hdl);
        // try self.onPinRewired(pin1_hdl);

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
        const results = try self.spatial_hash.query(
            self.allocator,
            world_pos,
            100.0,
        );

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
        _ = screen_pos;
        if (button == .left) {
            if (self.hover_handle_id == null and self.bounds.containsPoint(self.hover_pos)) {
                // _ = try self.spawnPin(self.hover_pos, false);
                var k = raylib.KEY_ZERO;
                var placed_gate = false;
                while (k <= raylib.KEY_NINE) : (k += 1) {
                    if (raylib.IsKeyDown(k)) {
                        var idx = if (k == raylib.KEY_ZERO) 9 else k - raylib.KEY_ONE;
                        var bp = GATE_BLUEPRINTS[@intCast(usize, idx)];
                        try self.spawnGate(&bp, self.hover_pos);
                        placed_gate = true;
                        break;
                    }
                }
                if (!placed_gate) {
                    if (raylib.IsKeyDown(raylib.KEY_Q)) {
                        _ = try self.spawnObject(.source, self.hover_pos);
                    } else {
                        _ = try self.spawnObject(.pin, self.hover_pos);
                    }
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
        try self.updateAllObjectsOfVariant(.pin, dt);
        try self.updateAllObjectsOfVariant(.source, dt);

        if (raylib.IsKeyPressed(raylib.KEY_Z)) {
            std.debug.print("\n", .{});
            self.csim.debugPrintState();
            try self.csim.logState();
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
            raylib.DrawLineEx(
                start.toRaylibVector2(),
                self.mouse_pos.toRaylibVector2(),
                Wire.WIRE_WIDTH,
                raylib.ORANGE,
            );
        }
    }
};

pub fn initiateCircuitSandbox() !void {
    const allocator = std.heap.c_allocator;
    const screen_width = 800;
    const screen_height = 600;
    const draw_grid_lines = true;
    const screen_size_f = Vec2(f32).init(
        @intToFloat(f32, screen_width),
        @intToFloat(f32, screen_height),
    );

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

    const chunk_size = Vec2(f32).fill(100);
    const draw_grid_options = gfx.grid.DrawGridOptions{
        .chunk_size = chunk_size,
        .world_bounds = world.bounds,
    };

    var cam = &(world.cam);
    var camCtrl = Cam2Controller(f32).init(cam);
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

        camCtrl.update(frame_time);

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
                gfx.grid.drawGrid(&world.cam, draw_grid_options);
            }

            try world._draw(frame_time);

            raylib.DrawRectangle(0, 0, screen_width, 40, raylib.BLACK);
            raylib.DrawText("Welcome to the Logiverse", 120, 10, 20, raylib.GREEN);
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
