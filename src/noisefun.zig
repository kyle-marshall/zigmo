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

const noise = root.noise;

const CELL_TEX_PATH = "resources/some-tile-1.png";
const VOID_COLOR = Color{ .r = 20, .g = 49, .b = 65, .a = 255 };
const SCREEN_GRID_UNIT = 20;

pub fn colorFromFloatValues(r: f32, g: f32, b: f32, a: f32) Color {
    // std.debug.print("{d},{d},{d},{d}\n", .{ r, g, b, a });
    return Color{
        .r = @floatToInt(u8, r * 255),
        .g = @floatToInt(u8, g * 255),
        .b = @floatToInt(u8, b * 255),
        .a = @floatToInt(u8, a * 255),
    };
}

pub fn enjoyTheNoise() !void {
    // const allocator = std.heap.c_allocator;
    const screen_width = 800;
    const screen_height = 600;
    const screen_size_f = Vec2(f32).init(
        @intToFloat(f32, screen_width),
        @intToFloat(f32, screen_height),
    );

    const screen_rect = Rect(f32).init(
        Vec2(f32).zero,
        screen_size_f,
    );
    _ = screen_rect;

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

    var seed = std.crypto.random.int(u64);
    var prng = std.rand.DefaultPrng.init(seed);
    var rng = prng.random();

    var camCtrl = Cam2Controller(f32).init(&cam);

    var r_plane_offset = Vec2(f32).init(0, 0);
    var g_plane_offset = Vec2(f32).init(rng.float(f32), 0);
    var b_plane_offset = Vec2(f32).init(0, rng.float(f32));

    const fun_div_max = 500;
    const r_div_x = rng.float(f32) * fun_div_max;
    const r_div_y = rng.float(f32) * fun_div_max;
    const g_div_x = rng.float(f32) * fun_div_max;
    const g_div_y = rng.float(f32) * fun_div_max;
    const b_div_x = rng.float(f32) * fun_div_max;
    const b_div_y = rng.float(f32) * fun_div_max;

    raylib.InitWindow(screen_width, screen_height, "noisefun");
    defer raylib.CloseWindow();
    raylib.SetWindowPosition(1920, 64);
    raylib.SetTargetFPS(60);

    var cell_tex = raylib.LoadTexture(CELL_TEX_PATH);

    const radius = SCREEN_GRID_UNIT / 2;
    var t: f32 = 0;
    while (!raylib.WindowShouldClose()) {
        const frame_time = raylib.GetFrameTime();
        camCtrl.update(frame_time);
        raylib.BeginDrawing();
        raylib.ClearBackground(VOID_COLOR);
        gfx.grid.drawGrid(&cam, draw_grid_options);

        const visible_rect = cam.visible_rect;

        var scaled_rad = radius * cam.curr_scale;
        var screen_points: [5]Vec2(f32) = undefined;
        inline for (0..5) |c_i| {
            screen_points[c_i] = root.gfx.RectTexCoords[c_i].subScalar(0.5).mulScalar(scaled_rad * 2);
        }

        const wx_start = @floor(visible_rect.origin.v[0] / SCREEN_GRID_UNIT) * SCREEN_GRID_UNIT;
        const wy_start = @floor(visible_rect.origin.v[1] / SCREEN_GRID_UNIT) * SCREEN_GRID_UNIT;
        var screen_start = cam.worldToScreen(Vec2(f32).init(wx_start, wy_start));
        var vox_x_step = Vec2(f32).init(SCREEN_GRID_UNIT * cam.curr_scale, 0);
        var vox_y_step = Vec2(f32).init(0, SCREEN_GRID_UNIT * cam.curr_scale);
        var screen_pos = Vec2(f32).init(screen_start.v[0], 0);
        var wx: f32 = wx_start;
        var wy: f32 = undefined;
        while (screen_pos.v[0] < screen_width) : (wx += SCREEN_GRID_UNIT) {
            wy = wy_start;
            screen_pos.v[1] = screen_start.v[1];
            while (screen_pos.v[1] < screen_height) : (wy += SCREEN_GRID_UNIT) {
                const s_r = (1.0 + noise.snoise2(
                    (t + wx + r_plane_offset.v[0]) / r_div_x,
                    (t + wy + r_plane_offset.v[1]) / r_div_y,
                )) / 2.0;
                const s_g = (1.0 + noise.snoise2(
                    (t + wx + g_plane_offset.v[0]) / g_div_x,
                    (t + wy + g_plane_offset.v[1]) / g_div_y,
                )) / 2.0;
                const s_b = (1.0 + noise.snoise2(
                    (t + wx + b_plane_offset.v[0]) / b_div_x,
                    (t + wy + b_plane_offset.v[1]) / b_div_y,
                )) / 2.0;
                const color = colorFromFloatValues(s_r, s_g, s_b, 1.0);
                // raylib.DrawCircleV(screen_pos.toRaylibVector2(), scaled_rad, color);
                root.gfx.drawTexturePoly(
                    cell_tex,
                    screen_pos,
                    screen_points[0..],
                    @constCast(root.gfx.RectTexCoords[0..]),
                    color,
                );
                _ = screen_pos.addInPlace(vox_y_step);
            }
            _ = screen_pos.addInPlace(vox_x_step);
        }
        t += frame_time * 10;

        raylib.EndDrawing();
    }
}
