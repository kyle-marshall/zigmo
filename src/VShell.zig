const std = @import("std");
const root = @import("root");
const raylib = root.raylib;
const math = root.math;
const Vec2 = math.Vec2;

const Self = @This();

font_size: f32 = 20,
view_right_pad: f32 = 50,
input_buffer: [INPUT_BUFF_LEN]u8 = undefined,
cursor_offset: usize = 0,
view_size: Vec2(f32) = Vec2(f32).zero,

const KEYCODES: []const u8 = " ',-./0123456789;=ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]`";
const LOWER_TO_UPPER: i8 = 'a' - 'A';
const SHIFTABLE_CHARS: []const u8 = "0123456789,./;'[]\\-=";
const SHIFT_CHAR_REPL: []const u8 = ")!@#$%^&*(<>?:\"{}|_+";
const INPUT_BUFF_LEN = 1024;

fn shiftFilter(c: u8, shift: bool) u8 {
    // special case
    if (c >= 'A' and c <= 'Z') {
        if (shift) return c;
        return @intCast(u8, @intCast(i8, c) + LOWER_TO_UPPER);
    }
    if (shift) {
        const n = SHIFTABLE_CHARS.len;
        for (0..n) |i| {
            if (c == SHIFTABLE_CHARS[i]) {
                return SHIFT_CHAR_REPL[i];
            }
        }
    }
    return c;
}

pub fn init() Self {
    var shell = Self{};
    @memset(&shell.input_buffer, 0);
    return shell;
}

pub fn update(self: *Self) void {
    const shift = raylib.IsKeyDown(raylib.KEY_LEFT_SHIFT) or raylib.IsKeyDown(raylib.KEY_RIGHT_SHIFT);
    for (KEYCODES) |c| {
        if (raylib.IsKeyPressed(c)) {
            const out_c = shiftFilter(c, shift);
            self.input_buffer[self.cursor_offset] = out_c;
            self.cursor_offset += 1;
            // const out_c = if (shift and isUpperCaseChar(c)) c + UPPERT_TO_LOWER else c;
            std.debug.print("pressed {c}\n", .{out_c});
            std.debug.print(
                "input buffer ({d}): {s}\n",
                .{ self.cursor_offset, self.input_buffer[0..self.cursor_offset] },
            );
        }
    }
    if (raylib.IsKeyPressed(raylib.KEY_BACKSPACE) and self.cursor_offset > 0) {
        if (shift) {
            @memset(&self.input_buffer, 0);
            self.cursor_offset = 0;
        } else {
            self.input_buffer[self.cursor_offset - 1] = 0;
            self.cursor_offset -= 1;
        }
    }
}

pub fn draw(self: *Self) void {
    const font = raylib.GetFontDefault();
    var size = raylib.MeasureTextEx(font, &self.input_buffer, self.font_size, 1);
    var txt_pos = Vec2(f32).init(10, 40);
    var wider_than_view: f32 = (size.x + self.view_right_pad) - self.view_size.v[0];
    if (wider_than_view > 0) {
        txt_pos.v[0] -= wider_than_view;
    }
    raylib.DrawTextEx(font, &self.input_buffer, txt_pos.toRaylibVector2(), self.font_size, 1, raylib.GREEN);
}

pub fn shellTest() !void {
    const screen_width: u32 = 800;
    const screen_height: u32 = 600;
    std.debug.print("{s}\n", .{KEYCODES});

    const screen_size = Vec2(u32).init(screen_width, screen_height).intToFloat(f32);

    raylib.InitWindow(screen_width, screen_height, "shellTest");
    raylib.SetTargetFPS(60);

    var shell = Self.init();
    shell.view_size = screen_size;

    while (!raylib.WindowShouldClose()) {
        shell.update();
        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.BLACK);
        raylib.DrawText("asdf", 120, 10, 20, raylib.GREEN);
        shell.draw();
        raylib.DrawFPS(10, 10);
        raylib.EndDrawing();
    }
}
