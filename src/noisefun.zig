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

fn randomVec2f32(rng: anytype) Vec2(f32) {
    return Vec2(f32).init(rng.float(f32), rng.float(f32));
}

const NoiseyHyperParams = struct {
    const Self = @This();
    r_plane_offset: Vec2(f32),
    g_plane_offset: Vec2(f32),
    b_plane_offset: Vec2(f32),
    r_div: Vec2(f32),
    g_div: Vec2(f32),
    b_div: Vec2(f32),

    pub fn random(rng: anytype) Self {
        const max_plane_offset = 1000;
        const r_plane_offset = Vec2(f32).init(rng.float(f32) * max_plane_offset, rng.float(f32) * max_plane_offset);
        const g_plane_offset = Vec2(f32).init(rng.float(f32) * max_plane_offset, rng.float(f32) * max_plane_offset);
        const b_plane_offset = Vec2(f32).init(rng.float(f32) * max_plane_offset, rng.float(f32) * max_plane_offset);

        const fun_div_max = 500;
        const r_div = randomVec2f32(rng).mulScalar(fun_div_max);
        const g_div = randomVec2f32(rng).mulScalar(fun_div_max);
        const b_div = randomVec2f32(rng).mulScalar(fun_div_max);

        return Self{
            .r_plane_offset = r_plane_offset,
            .g_plane_offset = g_plane_offset,
            .b_plane_offset = b_plane_offset,
            .r_div = r_div,
            .g_div = g_div,
            .b_div = b_div,
        };
    }
};

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

    var hyper_params = NoiseyHyperParams.random(rng);

    raylib.InitWindow(screen_width, screen_height, "noisefun");
    defer raylib.CloseWindow();
    raylib.SetWindowPosition(1920, 64);
    raylib.SetTargetFPS(60);

    const cell_tex = raylib.LoadTexture(CELL_TEX_PATH);

    var t: f32 = 0;
    while (!raylib.WindowShouldClose()) {
        const frame_time = raylib.GetFrameTime();
        camCtrl.update(frame_time);
        raylib.BeginDrawing();
        raylib.ClearBackground(VOID_COLOR);
        gfx.grid.drawGrid(&cam, draw_grid_options);

        if (raylib.IsKeyPressed(raylib.KEY_Z)) {
            hyper_params = NoiseyHyperParams.random(rng);
        }

        const visible_rect = cam.visible_rect;

        const min_vox_render_size = 5;
        var wdx: f32 = SCREEN_GRID_UNIT;
        var wdy: f32 = SCREEN_GRID_UNIT;
        var vox_x_step = Vec2(f32).init(wdx * cam.curr_scale, 0);
        var vox_y_step = Vec2(f32).init(0, wdy * cam.curr_scale);
        while (vox_x_step.v[0] < min_vox_render_size) {
            wdx += SCREEN_GRID_UNIT;
            vox_x_step = Vec2(f32).init(wdx * cam.curr_scale, 0);
        }
        while (vox_y_step.v[1] < min_vox_render_size) {
            wdy += SCREEN_GRID_UNIT;
            vox_y_step = Vec2(f32).init(0, wdy * cam.curr_scale);
        }

        const screen_cell_size = Vec2(f32).init(wdx * cam.curr_scale, wdy * cam.curr_scale);
        var screen_points: [5]Vec2(f32) = undefined;
        inline for (0..5) |c_i| {
            screen_points[c_i] = root.gfx.RectTexCoords[c_i].subScalar(0.5).mul(screen_cell_size);
        }

        const wx_start = @floor(visible_rect.origin.v[0] / wdx) * wdx;
        const wy_start = @floor(visible_rect.origin.v[1] / wdy) * wdy;
        var screen_start = cam.worldToScreen(Vec2(f32).init(wx_start, wy_start));
        var screen_pos = Vec2(f32).init(screen_start.v[0], 0);
        var wx: f32 = wx_start;
        var wy: f32 = undefined;
        const t_vec = Vec2(f32).fill(t).mulScalar(50);

        while (screen_pos.v[0] < screen_width + vox_x_step.v[0]) : (wx += wdx) {
            wy = wy_start;
            screen_pos.v[1] = screen_start.v[1];
            while (screen_pos.v[1] < screen_height + vox_y_step.v[1]) : (wy += wdy) {
                const w_pos = Vec2(f32).init(wx, wy);
                const r_pos = t_vec.add(w_pos).add(hyper_params.r_plane_offset).div(hyper_params.r_div);
                const g_pos = t_vec.add(w_pos).add(hyper_params.g_plane_offset).div(hyper_params.g_div);
                const b_pos = t_vec.add(w_pos).add(hyper_params.b_plane_offset).div(hyper_params.b_div);
                const s_r = (1.0 + noise.snoise2v(r_pos)) / 2.0;
                const s_g = (1.0 + noise.snoise2v(g_pos)) / 2.0;
                const s_b = (1.0 + noise.snoise2v(b_pos)) / 2.0;
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
        t += frame_time;
        raylib.DrawFPS(10, 10);
        raylib.DrawText("Press Z to randomize", 100, 10, 20, raylib.PINK);
        raylib.EndDrawing();
    }
}
