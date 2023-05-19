const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;
const TailQueue = std.TailQueue;
const AutoArrayHashMap = std.AutoArrayHashMap;

pub const raylib = @cImport(@cInclude("raylib.h"));
pub const rlgl = @cImport(@cInclude("rlgl.h"));
const Color = raylib.Color;
const Texture = raylib.Texture;

const util = @import("root").util;
const math = @import("root").math;
const Vec2 = math.Vec2;
const Mat3 = math.Mat3;
const Rect = math.geo.Rect;

const circuit_simulator = @import("circuit_simulator.zig");
const CircuitSimulator = circuit_simulator.CircuitSimulator;
const LogicValue = circuit_simulator.LogicValue;
const NetId = circuit_simulator.NetId;
const GateId = circuit_simulator.GateId;
const NetTableEntry = circuit_simulator.NetTableEntry;
const GateTableEntry = circuit_simulator.GateTableEntry;
const SimulateGateFn = circuit_simulator.SimulateGateFn;

const MouseButton = enum { left, right, middle };
const LineSegment = struct {
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

const BW_WIDTH = 1000;
const BW_HEIGHT = 1000;
const BW_ORIGIN_X = BW_WIDTH / 2;
const BW_ORIGIN_Y = BW_HEIGHT / 2;
const BW_MAX_OBJECTS = 1_000_000;
const BW_MAX_INITIAL_SPEED = 50.0; // world units per second
const BW_INSTA_SPAWN_BATCH_SIZE = 10;

const PIN_TEX_PATH = "resources/pin.png";

const MINOR_GRID_LINE_COLOR = Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
const MAJOR_GRID_LINE_COLOR = Color{ .r = 100, .g = 100, .b = 100, .a = 255 };

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

const ObjectVariant = enum { pin, component };

const ObjectTag = struct {
    variant: ObjectVariant,
    index: usize,
};

// in the Logiverse, NetTableEntries, or "nets" for short,
// are tied to their virtually-physical representations "pins"
// in other words, a pin is the render info for a net
const PinId = usize;
const Pin = struct {
    pin_id: PinId,
    net_id: NetId,
    /// whether or not the pin is linked to a net
    is_connected: bool,
    position: Vec2(f32),
    adj_pins: ArrayList(PinId),
    dependant_comps: ArrayList(CompId),
    pub fn init(allocator: Allocator, pin_id: PinId, position: Vec2(f32)) Pin {
        return Pin{
            .pin_id = pin_id,
            .net_id = 0,
            .is_connected = false,
            .position = position,
            .adj_pins = ArrayList(PinId).init(allocator),
            .dependant_comps = ArrayList(CompId).init(allocator),
        };
    }

    pub fn deinit(self: *Pin) void {
        self.adj_pins.deinit();
    }
};

const CompId = usize;
const Component = struct {
    comp_id: CompId,
    gate_id: GateId,
    /// owned pins will move with the component when it is moved
    in_pins: ArrayList(PinId),
    out_pins: ArrayList(PinId),
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
            .in_pins = ArrayList(PinId).init(allocator),
            .out_pins = ArrayList(PinId).init(allocator),
            .color = color,
        };
    }
};

const BlueprintId = usize;
const ComponentBlueprint = struct {
    id: BlueprintId,
    rect: Rect(f32),
    color: Color,
    input_positions: ArrayList(Vec2(f32)),
    output_positions: ArrayList(Vec2(f32)),
    simulate_fn: SimulateGateFn,
};

const BlueprintFactory = struct {
    pub fn _and(csim: *CircuitSimulator, gate_ptr: *GateTableEntry) LogicValue {
        for (gate_ptr.inputs.items) |net_id| {
            if (!csim.getValue(net_id)) {
                return false;
            }
        }
        return true;
    }
    pub fn and2(allocator: Allocator) !ComponentBlueprint {
        var blueprint = ComponentBlueprint{
            .id = 0,
            .rect = Rect(f32).init(Vec2(f32).zero, Vec2(f32).init(30, 40)),
            .input_positions = ArrayList(Vec2(f32)).init(allocator),
            .output_positions = ArrayList(Vec2(f32)).init(allocator),
            .color = raylib.PINK,
            .simulate_fn = _and,
        };
        try blueprint.input_positions.append(Vec2(f32).init(5, 10));
        try blueprint.input_positions.append(Vec2(f32).init(5, 30));
        try blueprint.output_positions.append(Vec2(f32).init(25, 20));
        return blueprint;
    }
};

const LogiverseEvent = struct {
    net_id: usize,
    value: LogicValue,
};

const Logiverse = struct {
    const Self = @This();
    const SpatialHash = geo.spatial_hash.SpatialHash(f32, usize);

    // circuit fun
    csim: CircuitSimulator,

    // world state
    world_size: Vec2(f32),
    bounds: Rect(f32),
    pins: ArrayList(Pin),
    components: ArrayList(Component),
    obj_tags: ArrayList(ObjectTag),

    // world action state
    is_wiring: bool,
    wire_start_pin: PinId,

    // qt: QuadTree,
    spatial_hash: SpatialHash,

    // view state
    screen_size: Vec2(f32),
    cam: Cam2(f32),
    mouse_pos: Vec2(f32),
    pan_start: Vec2(f32),
    is_panning: bool,

    free_net_ids: ArrayList(NetId),

    // resources
    allocator: Allocator,
    resource_manager: ResourceManager,

    pub fn init(allocator: Allocator, world_size: Vec2(f32), screen_size: Vec2(f32)) !Self {
        const bounds = Rect(f32).init(Vec2(f32).zero, world_size);
        var obj = Self{
            .allocator = allocator,
            .csim = try CircuitSimulator.init(allocator),
            .world_size = world_size,
            .screen_size = screen_size,
            .bounds = Rect(f32).init(Vec2(f32).zero, world_size),
            .spatial_hash = try SpatialHash.init(
                allocator,
                bounds,
                100.0,
            ),
            .cam = Cam2(f32).init(screen_size, Mat3(f32).identity),
            .pins = ArrayList(Pin).init(allocator),
            .components = ArrayList(Component).init(allocator),
            .resource_manager = ResourceManager.init(allocator),
            .obj_tags = ArrayList(ObjectTag).init(allocator),
            .pan_start = Vec2(f32).zero,
            .mouse_pos = Vec2(f32).zero,
            .is_panning = false,
            .is_wiring = false,
            .wire_start_pin = 0,
            .free_net_ids = ArrayList(NetId).init(allocator),
        };

        try obj.resource_manager.loadTexture(PIN_TEX_PATH);

        obj.cam.centerOnInstant(Vec2(f32).init(0, 0));
        // add 10 input pins for testing
        for (0..10) |i| {
            const pin_id = try obj.spawnPin(Vec2(f32).init(20, (@intToFloat(f32, i) + 1) * 20), true);
            const net_id = obj.pins.items[pin_id].net_id;
            obj.csim.net_table.items[net_id].is_input = true;
            try obj.csim.external_inputs.append(net_id);
        }

        return obj;
    }

    pub fn deinit(self: *Self) void {
        self.csim.deinit();
    }

    pub fn createObjectTag(self: *Self, variant: ObjectVariant, index: usize) !usize {
        const tag_index = self.obj_tags.items.len;
        try self.obj_tags.append(ObjectTag{
            .variant = variant,
            .index = index,
        });
        return tag_index;
    }

    pub fn spawnPin(self: *Self, world_pos: Vec2(f32), with_net: bool) !PinId {
        std.log.info("spawning pin at: ({d}, {d})", .{ world_pos.v[0], world_pos.v[1] });
        const pinId = self.pins.items.len;
        try self.pins.append(Pin.init(self.allocator, pinId, world_pos));
        const tagId = try self.createObjectTag(.pin, pinId);
        _ = try self.spatial_hash.insert(world_pos, tagId);
        if (with_net) {
            const net_id = try self.csim.addNet(false);
            self.pins.items[pinId].net_id = net_id;
            self.pins.items[pinId].is_connected = true;
        }
        return pinId;
    }

    pub fn spawnComponentBlueprint(self: *Self, bp: *ComponentBlueprint, world_pos: Vec2(f32)) !void {
        const gate_id = self.csim.gate_table.items.len;

        try self.csim.gate_table.append(GateTableEntry{
            .id = gate_id,
            .inputs = ArrayList(NetId).init(self.allocator),
            .is_stale = true,
            .outputs = ArrayList(NetId).init(self.allocator),
            .simulate = bp.simulate_fn,
        });

        const comp_id = self.components.items.len;
        for (bp.input_positions.items) |pos| {
            const pin_id = try self.spawnPin(world_pos.add(pos), true);
            var pin = &self.pins.items[pin_id];
            var net = &self.csim.net_table.items[pin.net_id];
            try net.fanout.append(gate_id);
            try self.csim.gate_table.items[gate_id].inputs.append(pin.net_id);
            // pin.dependant_comps.append(comp_id);
        }

        for (bp.output_positions.items) |pos| {
            const pin_id = try self.spawnPin(world_pos.add(pos), true);
            try self.csim.gate_table.items[gate_id].outputs.append(self.pins.items[pin_id].net_id);
        }

        var rect = bp.rect;
        _ = rect.origin.addInPlace(world_pos);
        try self.components.append(Component.init(self.allocator, comp_id, gate_id, world_pos, rect, bp.color));
        const tag_id = try self.createObjectTag(.component, comp_id);
        _ = try self.spatial_hash.insert(world_pos, tag_id);
    }

    pub inline fn check_pin_adjacency(self: *Self, pin_a_id: PinId, pin_b_id: PinId) bool {
        var pin_a = &self.pins.items[pin_a_id];
        for (pin_a.adj_pins.items) |item| {
            if (item == pin_b_id) return true;
        }
        return false;
    }

    pub fn wire(self: *Self, pin_a_id: PinId, pin_b_id: PinId) !void {
        if (pin_a_id == pin_b_id) {
            std.log.info("those are the same pins, you fool!", .{});
            return;
        }
        std.log.info("wire from {} to {}", .{ pin_a_id, pin_b_id });
        if (self.check_pin_adjacency(pin_a_id, pin_b_id)) {
            std.log.info("pins are already wired. abort!", .{});
            return;
        }
        var pin_a = &self.pins.items[pin_a_id];
        var pin_b = &self.pins.items[pin_b_id];
        if (pin_a.is_connected and pin_b.is_connected) {
            // merge corresponding nets (no directionality preference... yet)
            try self.csim.merge_nets(pin_a.net_id, pin_b.net_id);
            for (self.pins.items) |*pin| {
                if (pin.net_id == pin_b.net_id) pin.net_id = pin_a.net_id;
            }
        } else if (pin_a.is_connected and !pin_b.is_connected) {
            // pin_b joins pin_a's net
            pin_b.net_id = pin_a.net_id;
        } else if (pin_b.is_connected and !pin_a.is_connected) {
            // pin_a joins pin_b's net
            pin_a.net_id = pin_b.net_id;
        } else {
            // neither are connected, create a new net
            const net_id = try self.csim.addNet(false);
            pin_a.net_id = net_id;
            pin_b.net_id = net_id;
        }
        try pin_a.adj_pins.append(pin_b_id);
        try pin_b.adj_pins.append(pin_a_id);
        pin_a.is_connected = true;
        pin_b.is_connected = true;

        var net_a = &self.csim.net_table.items[pin_a.net_id];
        var net_b = &self.csim.net_table.items[pin_a.net_id];

        // trigger re-simulation
        if (net_a.is_input) net_a.is_undefined = true;
        if (net_b.is_input) net_b.is_undefined = true;

        self.csim.printNetTable();
    }

    pub fn findPinAtPosition(self: *Self, world_pos: Vec2(f32)) !?PinId {
        if (!self.bounds.containsPoint(world_pos)) return null;
        const results = try self.spatial_hash.query(self.allocator, world_pos, 50.0);
        for (results.items) |*item| {
            const tagId = item.point_data.data;
            const tag = self.obj_tags.items[tagId];
            if (tag.variant == .pin and item.distance < PIN_WORLD_RADIUS) {
                return tag.index;
            }
        }
        return null;
    }

    pub fn _mouseButtonDown(self: *Self, button: MouseButton, screen_pos: Vec2(f32)) !void {
        if (button == .left) {
            const world_pos = self.cam.screenToWorld(screen_pos);
            if (self.bounds.containsPoint(world_pos)) {
                const results = try self.spatial_hash.query(self.allocator, world_pos, 50.0);
                var clicked_object = false;
                for (results.items) |*item| {
                    const tagId = item.point_data.data;
                    const tag = self.obj_tags.items[tagId];
                    if (tag.variant == .pin and item.distance < PIN_WORLD_RADIUS) {
                        clicked_object = true;
                        self.is_wiring = true;
                        std.log.info("start wiring from pin {}", .{tag.index});
                        self.wire_start_pin = tag.index;
                        break;
                    }
                    if (tag.variant == .component) {
                        var component = self.components.items[tag.index];
                        if (component.rect.containsPoint(world_pos)) {
                            clicked_object = true;
                            // TODO start dragging component
                            std.log.info("clicked component {}", .{tag.index});
                        } else {
                            std.log.info("nearby component wasn't clicked...", .{});
                            component.rect.debugPrint();
                        }
                    }
                }
                if (!clicked_object) {
                    _ = try self.spawnPin(world_pos, false);
                }
            } else {
                std.log.info("OOB clicked", .{});
            }
        } else if (button == .right) {
            std.log.info("right mouse down - noop", .{});
            const world_pos = self.cam.screenToWorld(screen_pos);
            if (self.bounds.containsPoint(world_pos)) {
                var bp = try BlueprintFactory.and2(self.allocator);
                try self.spawnComponentBlueprint(&bp, world_pos);
            }
        } else {
            self.pan_start = screen_pos;
            self.is_panning = true;
            std.log.info("pan start", .{});
        }
    }

    pub fn _mouseButtonUp(self: *Self, button: MouseButton, screen_pos: Vec2(f32)) !void {
        if (button == .left) {
            if (self.is_wiring) {
                const world_pos = self.cam.screenToWorld(screen_pos);
                const maybe_pin_id = try self.findPinAtPosition(world_pos);
                if (maybe_pin_id == null) {
                    std.log.info("cancel wire", .{});
                } else {
                    const pin_id = maybe_pin_id.?;
                    try self.wire(self.wire_start_pin, pin_id);
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
        }
    }

    pub fn _update(self: *Self, dt: f32) !void {
        if (raylib.IsKeyDown(raylib.KEY_ONE)) {
            const net_id = self.csim.external_inputs.items[0];
            // const prev = self.net_table.items[net_id].external_signal;
            self.csim.net_table.items[net_id].external_signal = true;
        }
        if (raylib.IsKeyDown(raylib.KEY_Z)) {
            std.debug.print("\n", .{});
            self.csim.printNetTable();
        }
        _ = dt;
        try self.csim.simulate();
    }

    pub fn _draw(self: *Self) !void {
        // COMPONENT RECTS
        for (self.components.items) |*comp| {
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
        var wires_to_draw = ArrayList(LineSegment).init(self.allocator);
        defer wires_to_draw.deinit();
        for (self.pins.items, 0..) |*pin, pin_id| {
            const is_active = if (!pin.is_connected) false else self.csim.getValue(pin.net_id);
            const color = if (is_active) raylib.YELLOW else raylib.GRAY;
            const world_pos = pin.position;
            if (pin_id == self.wire_start_pin) {
                wire_start_world_pos = world_pos;
            }
            if (!self.cam.visible_rect.containsPoint(world_pos)) {
                continue;
            }
            const screen_pos = self.cam.worldToScreen(world_pos);
            gfx.drawTexturePoly(
                pin_tex,
                screen_pos,
                screen_points[0..],
                @constCast(RectTexCoords[0..]),
                color,
            );
            for (pin.adj_pins.items) |adj_pin_id| {
                if (adj_pin_id > pin_id) {
                    try wires_to_draw.append(LineSegment{
                        .a = world_pos,
                        .b = self.pins.items[adj_pin_id].position,
                        .color = color,
                    });
                }
            }
        }
        for (wires_to_draw.items) |line_seg| {
            const screen_a = self.cam.worldToScreen(line_seg.a).toRaylibVector2();
            const screen_b = self.cam.worldToScreen(line_seg.b).toRaylibVector2();
            raylib.DrawLineEx(screen_a, screen_b, 2, line_seg.color);
        }
        if (self.is_wiring) {
            const start = self.cam.worldToScreen(wire_start_world_pos);
            raylib.DrawLineEx(start.toRaylibVector2(), self.mouse_pos.toRaylibVector2(), 2, raylib.ORANGE);
        }
    }

    pub fn pointQuery(self: *Self, point: Vec2(f32)) !void {
        const search_radius = 10;
        var results = try self.spatial_hash.query(self.allocator, point, search_radius);
        if (results.items.len == 0) {
            std.log.info("no elements in sight", .{});
            return;
        }
        var greatest_index: usize = 0;
        for (results.items) |item| {
            const index = item.point_data.data;
            if (index > greatest_index) {
                greatest_index = index;
            }
        }
        std.log.info("pointQuery found index: {}", .{greatest_index});
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
            true => if (!prev_is_right_mouse_down) try world._mouseButtonDown(.left, mouse_pos),
            false => if (prev_is_right_mouse_down) try world._mouseButtonUp(.left, mouse_pos),
        }
        switch (is_middle_mouse_down) {
            true => if (!prev_is_middle_mouse_down) try world._mouseButtonDown(.left, mouse_pos),
            false => if (prev_is_middle_mouse_down) try world._mouseButtonUp(.left, mouse_pos),
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
            raylib.ClearBackground(raylib.RAYWHITE);

            // GRID LINES
            if (draw_grid_lines) {
                var grid_size = world.bounds.size.div(Vec2(f32).init(grid_div, grid_div));
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
