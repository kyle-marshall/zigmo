const root = @import("root");

const raylib = root.raylib;
const Color = raylib.Color;

const math = root.math;
const Rect = math.geo.Rect;
const Vec2 = math.Vec2;

const Cam2 = root.cam.Cam2;

const DEFAULT_GRID_BG_COLOR = Color{ .r = 65, .g = 94, .b = 120, .a = 255 };
const DEFAULT_MINOR_GRID_LINE_COLOR = Color{ .r = 63, .g = 108, .b = 155, .a = 255 };
const DEFAULT_MAJOR_GRID_LINE_COLOR = Color{ .r = 90, .g = 135, .b = 169, .a = 255 };
const DEFAULT_CHUNK_DIVS = 8;

pub const DrawGridOptions = struct {
    world_bounds: Rect(f32),
    chunk_size: Vec2(f32),
    chunk_divs: u32 = DEFAULT_CHUNK_DIVS,
    bg_color: Color = DEFAULT_GRID_BG_COLOR,
    minor_line_color: Color = DEFAULT_MINOR_GRID_LINE_COLOR,
    major_line_color: Color = DEFAULT_MAJOR_GRID_LINE_COLOR,
};

pub fn drawGrid(cam: *Cam2(f32), options: DrawGridOptions) void {
    const wbounds = options.world_bounds;
    const wsize = wbounds.size;
    const grid_size = wsize.div(options.chunk_size);
    const screen_rect = cam.worldToScreenRect(options.world_bounds);
    raylib.DrawRectangleV(
        screen_rect.origin.toRaylibVector2(),
        screen_rect.size.toRaylibVector2(),
        options.bg_color,
    );
    var world_x: f32 = 0;
    var c: u32 = 0;
    while (world_x <= wsize.v[0]) : ({
        world_x += grid_size.v[0];
        c += 1;
    }) {
        const s0 = cam.worldToScreen(Vec2(f32).init(world_x, 0));
        const s1 = cam.worldToScreen(Vec2(f32).init(world_x, wsize.v[1]));
        var color = options.minor_line_color;
        var w: f32 = 1;
        if (c % options.chunk_divs == 0) {
            color = options.major_line_color;
            w = 2;
        }
        raylib.DrawLineEx(s0.toRaylibVector2(), s1.toRaylibVector2(), w, color);
    }
    var world_y: f32 = 0;
    c = 0;
    while (world_y <= wsize.v[1]) : ({
        world_y += grid_size.v[1];
        c += 1;
    }) {
        const s0 = cam.worldToScreen(Vec2(f32).init(0, world_y));
        const s1 = cam.worldToScreen(Vec2(f32).init(wsize.v[0], world_y));
        var color = options.minor_line_color;
        var w: f32 = 1;
        if (c % options.chunk_divs == 0) {
            color = options.major_line_color;
            w = 2;
        }
        raylib.DrawLineEx(s0.toRaylibVector2(), s1.toRaylibVector2(), w, color);
    }
}
