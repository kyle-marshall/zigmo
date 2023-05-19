const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoArrayHashMap = std.AutoArrayHashMap;

pub const raylib = @cImport(@cInclude("raylib.h"));
pub const rlgl = @cImport(@cInclude("rlgl.h"));
const Color = raylib.Color;

const util = @import("root").util;

const math = @import("root").math;
const Vec2 = math.Vec2;
const Mat3 = math.Mat3;
const Rect = math.geo.Rect;

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
const BW_INSTA_SPAWN_BATCH_SIZE = 50;
const BW_BUNNY_TEX_PATH = "resources/wabbit_alpha.png";

const MINOR_GRID_LINE_COLOR = Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
const MAJOR_GRID_LINE_COLOR = Color{ .r = 100, .g = 100, .b = 100, .a = 255 };

const Bunny = struct {
    position: Vec2(f32),
    speed: Vec2(f32),
    color: Color,
};

const BunnyWorld = struct {
    const Self = @This();
    const SpatialHash = geo.spatial_hash.SpatialHash(f32, usize);

    // world state
    world_size: Vec2(f32),
    bounds: Rect(f32),
    bunnies: std.ArrayList(Bunny),
    // qt: QuadTree,
    spatial_hash: SpatialHash,

    follow_mode: bool,
    follow_bunny_index: usize,

    // view state
    screen_size: Vec2(f32),
    cam: Cam2(f32),

    // resources
    allocator: Allocator,
    bunny_tex: raylib.Texture2D,
    bunny_tex_size: Vec2(f32),

    const BunnyTexCoords = [5]Vec2(f32){
        Vec2(f32).init(0, 0),
        Vec2(f32).init(0, 1),
        Vec2(f32).init(1, 1),
        Vec2(f32).init(1, 0),
        Vec2(f32).init(0, 0),
    };

    pub fn init(allocator: Allocator, world_size: Vec2(f32), screen_size: Vec2(f32)) !Self {
        const bounds = Rect(f32).init(Vec2(f32).zero, world_size);
        var bunny_tex = raylib.LoadTexture(BW_BUNNY_TEX_PATH);
        var bunny_tex_size = Vec2(f32).init(
            @intToFloat(f32, bunny_tex.width),
            @intToFloat(f32, bunny_tex.height),
        );
        var obj = Self{
            .allocator = allocator,
            .world_size = world_size,
            .screen_size = screen_size,
            .bounds = Rect(f32).init(Vec2(f32).zero, world_size),
            .bunnies = ArrayList(Bunny).init(allocator),
            .spatial_hash = try SpatialHash.init(
                allocator,
                bounds,
                100.0,
            ),
            .bunny_tex = bunny_tex,
            .bunny_tex_size = bunny_tex_size,
            .cam = Cam2(f32).init(screen_size, Mat3(f32).identity),
            .follow_mode = false,
            .follow_bunny_index = 0,
        };
        return obj;
    }

    pub fn deinit(self: *BunnyWorld) void {
        self.bunnies.deinit();
        defer raylib.UnloadTexture(self.bunny_tex);
    }

    pub fn addBunny(self: *BunnyWorld, bunny: Bunny) !usize {
        const index = self.bunnies.items.len;
        try self.bunnies.append(bunny);
        _ = try self.spatial_hash.insert(bunny.position, index);
        if (index == 0) {
            self.follow_bunny_index = 0;
            self.follow_mode = true;
        }
        return index;
    }

    pub fn batchSpawn(self: *BunnyWorld, where: Vec2(f32), count: usize) !void {
        const random_seed = std.crypto.random.int(u64);
        var rng = std.rand.DefaultPrng.init(random_seed);
        var obj_count = self.bunnies.items.len;
        for (0..count) |_| {
            if (obj_count < BW_MAX_OBJECTS) {
                _ = try self.addBunny(Bunny{
                    .position = where,
                    .speed = Vec2(f32).init(
                        rng.random().float(f32) * BW_MAX_INITIAL_SPEED * 2.0 - BW_MAX_INITIAL_SPEED,
                        rng.random().float(f32) * BW_MAX_INITIAL_SPEED * 2.0 - BW_MAX_INITIAL_SPEED,
                    ),
                    .color = Color{
                        .r = @mod(rng.random().int(u8), 200) + 55,
                        .g = @mod(rng.random().int(u8), 200) + 55,
                        .b = @mod(rng.random().int(u8), 200) + 55,
                        .a = 255,
                    },
                });
                obj_count += 1;
            } else {
                std.log.warn("max bunny count reached", .{});
                break;
            }
        }
    }

    pub fn pointQuery(self: *BunnyWorld, point: Vec2(f32)) !void {
        const search_radius = 10;
        var results = try self.spatial_hash.query(self.allocator, point, search_radius);
        if (results.items.len == 0) {
            std.log.info("no bunnies in sight", .{});
            return;
        }
        var greatest_index: usize = 0;
        for (results.items) |item| {
            const index = item.point_data.data;
            if (index > greatest_index) {
                greatest_index = index;
            }
        }
        self.follow_bunny_index = greatest_index;
    }

    pub inline fn getBunny(self: *BunnyWorld, index: usize) !*Bunny {
        return &self.bunnies.items[index];
    }

    pub fn moveBunny(self: *BunnyWorld, index: usize, new_position: Vec2(f32)) !void {
        if (!self.bounds.containsPoint(new_position)) {
            const x = new_position.v[0];
            const y = new_position.v[1];
            std.log.warn("bunny {d} tried to moved out of bounds to ({d}, {d})\n", .{ index, x, y });
            return;
        }
        const bunny = try self.getBunny(index);
        bunny.position = new_position;
        // const maybe_last_pos = self.qt.getLastKnownPosition(index);
        const maybe_last_pos = null;
        if (maybe_last_pos == null) {
            _ = try self.spatial_hash.move(index, new_position);
        }
    }

    pub fn _update(self: *BunnyWorld, dt: f32) !void {
        for (self.bunnies.items, 0..) |*bunny, i| {
            const p_f = self.bounds.clampPoint(bunny.position.add(bunny.speed.mulScalar(dt)));
            try self.moveBunny(i, p_f);
            if (self.bounds.isExactlyMaxValueX(p_f.v[0]) or p_f.v[0] == 0) {
                bunny.speed.v[0] *= -1.0;
            }
            if (self.bounds.isExactlyMaxValueY(p_f.v[1]) or p_f.v[1] == 0) {
                bunny.speed.v[1] *= -1.0;
            }
            if (self.follow_mode and i == self.follow_bunny_index) {
                self.cam.centerOnSmooth(bunny.position, dt);
            }
        }
    }

    pub fn _draw(self: *BunnyWorld) void {
        // BUNNIES
        const bunny_size = self.bunny_tex_size.mulScalar(self.cam.curr_scale);
        var follow_bunny_is_visible = false;
        var follow_bunny_screen_pos: Vec2(f32) = undefined;
        var screen_points: [5]Vec2(f32) = undefined;
        inline for (0..5) |c_i| {
            screen_points[c_i] = BunnyTexCoords[c_i].subScalar(0.5).mul(bunny_size);
        }
        for (self.bunnies.items, 0..) |*bunny, i| {
            const world_pos = bunny.position;
            if (self.cam.visible_rect.containsPoint(world_pos)) {
                const screen_pos = self.cam.worldToScreen(world_pos);
                gfx.drawTexturePoly(self.bunny_tex, screen_pos, screen_points[0..], @constCast(BunnyTexCoords[0..]), bunny.color);
                if (self.follow_mode and i == self.follow_bunny_index) {
                    follow_bunny_screen_pos = screen_pos;
                    follow_bunny_is_visible = true;
                }
            }
        }
        if (follow_bunny_is_visible) {
            raylib.DrawCircleSectorLines(follow_bunny_screen_pos.toRaylibVector2(), bunny_size.max(), 0, 360, 1, raylib.MAGENTA);
        }
    }
};

pub fn bunnyTest() !void {
    const random_seed = std.crypto.random.int(u64);
    var rng = std.rand.DefaultPrng.init(random_seed);
    _ = rng;

    const allocator = std.heap.c_allocator;
    const screen_width = 800;
    const screen_height = 600;
    const draw_grid_lines = true;
    const screen_size_f = Vec2(f32).init(@intToFloat(f32, screen_width), @intToFloat(f32, screen_height));

    const grid_div = 100;
    var pan_speed: f32 = 10;
    var zoom_speed: f32 = 1.1;
    var biggest_dt: f32 = 0;

    raylib.InitWindow(screen_width, screen_height, "transform_test");
    defer raylib.CloseWindow();

    var world = try BunnyWorld.init(
        allocator,
        Vec2(f32).init(BW_WIDTH, BW_HEIGHT),
        screen_size_f,
    );
    defer world.deinit();

    var cam = &(world.cam);

    raylib.SetTargetFPS(60);
    var slowest_update_ms: u64 = 0;
    var slowest_draw_ms: u64 = 0;

    while (!raylib.WindowShouldClose()) {
        const frame_time = raylib.GetFrameTime();
        if (frame_time > biggest_dt) {
            std.log.info("slowest frame_time: {d}", .{biggest_dt});
            biggest_dt = frame_time;
        }
        const left_mouse_down = raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_LEFT);
        const right_mouse_down = raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_RIGHT);

        if (left_mouse_down or right_mouse_down) {
            const mouse_pos = Vec2(f32).fromRaylibVector2(raylib.GetMousePosition());
            const mouse_pos_w = cam.screenToWorld(mouse_pos);
            if (world.bounds.containsPoint(mouse_pos_w)) {
                if (left_mouse_down) {
                    try world.pointQuery(mouse_pos_w);
                } else if (right_mouse_down) {
                    try world.batchSpawn(mouse_pos_w, BW_INSTA_SPAWN_BATCH_SIZE);
                }
            }
        }

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

        // Update bunnies
        {
            const t0 = std.time.milliTimestamp();
            try world._update(frame_time);
            const t1 = std.time.milliTimestamp();
            const dt = @intCast(u64, t1 - t0);
            if (dt > slowest_update_ms) {
                slowest_update_ms = dt;
                std.debug.print("Slowest update: {d} ms\n", .{dt});
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

            world._draw();

            raylib.DrawRectangle(0, 0, screen_width, 40, raylib.BLACK);
            raylib.DrawText("bunnies: ", 120, 10, 20, raylib.GREEN);
            const obj_count = world.bunnies.items.len;
            const count_txt = try std.fmt.allocPrint(allocator, "{d}", .{obj_count});
            defer allocator.free(count_txt);
            const count_c_str = try util.makeNullTerminatedString(allocator, count_txt);
            defer allocator.free(count_c_str);

            raylib.DrawText(&count_c_str[0], 200, 10, 20, raylib.GREEN);
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
