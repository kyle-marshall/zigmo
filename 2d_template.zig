const std = @import("std");

const root = @import("root");
const raylib = root.raylib;
const Color = raylib.Color;

const math = root.math;
const Vec2 = math.Vec2;
const Mat3 = math.Mat3;
const Rect = math.geo.Rect;
const Cam2 = root.cam.Cam2;
const Cam2Controller = root.cam.Cam2Controller;
const gfx = root.gfx;

const VOID_COLOR = Color{ .r = 20, .g = 49, .b = 65, .a = 255 };

pub fn enjoyTheNoise() !void {
    // const allocator = std.heap.c_allocator;
    const screen_width = 800;
    const screen_height = 600;
    const screen_size_f = Vec2(f32).init(
        @intToFloat(f32, screen_width),
        @intToFloat(f32, screen_height),
    );

    const world_size = Vec2(f32).fill(1000);
    const world_origin = Vec2(f32).zero;
    const world_bounds = Rect(f32).init(world_origin, world_size);

    const chunk_size = Vec2(f32).fill(100);
    const draw_grid_options = gfx.grid.DrawGridOptions{
        .chunk_size = chunk_size,
        .world_bounds = world_bounds,
    };

    var cam = Cam2(f32).init(screen_size_f, Mat3(f32).identity);
    cam.centerOnInstant(Vec2(f32).init(200, 150));

    var camCtrl = Cam2Controller(f32).init(&cam);

    raylib.InitWindow(screen_width, screen_height, "transform_test");
    defer raylib.CloseWindow();
    raylib.SetWindowPosition(1920, 64);
    raylib.SetTargetFPS(60);

    while (!raylib.WindowShouldClose()) {
        const frame_time = raylib.GetFrameTime();
        camCtrl.update(frame_time);
        raylib.BeginDrawing();
        raylib.ClearBackground(VOID_COLOR);
        gfx.grid.drawGrid(&cam, draw_grid_options);
        raylib.EndDrawing();
    }
}
