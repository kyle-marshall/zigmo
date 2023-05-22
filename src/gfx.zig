const std = @import("std");

const raylib = @import("root").raylib;
const rlgl = @import("root").rlgl;
const Color = raylib.Color;

const math = @import("root").math;
const Vec2 = math.Vec2;

pub fn drawTexturePoly(texture: raylib.Texture2D, center: Vec2(f32), points: []Vec2(f32), texcoords: []Vec2(f32), tint: Color) void {
    rlgl.rlSetTexture(texture.id);
    rlgl.rlBegin(rlgl.RL_QUADS);
    rlgl.rlColor4ub(tint.r, tint.g, tint.b, tint.a);
    for (points, 0..) |point, i| {
        if (i == points.len - 1) {
            break;
        }
        rlgl.rlTexCoord2f(texcoords[i].v[0], texcoords[i].v[1]);
        rlgl.rlVertex2f(point.v[0] + center.v[0], point.v[1] + center.v[1]);
    }
    rlgl.rlEnd();
    rlgl.rlSetTexture(0);
}

const VerticalAlign = enum {
    top,
    center,
    bottom,
};

pub fn drawTextCentered(text: []const u8, pos: Vec2(f32), font_size: f32, spacing: f32, v_align: VerticalAlign, color: Color) void {
    var font = raylib.GetFontDefault();
    var size = raylib.MeasureTextEx(font, &text[0], font_size, 1);
    var y_offset = switch (v_align) {
        .top => 0,
        .center => -(size.y / 2),
        .bottom => -size.y,
    };
    var x_offset = -(size.x / 2);
    var txt_pos = pos.add(Vec2(f32).init(x_offset, y_offset));
    raylib.DrawTextEx(font, &text[0], txt_pos.toRaylibVector2(), font_size, spacing, color);
}

pub const RectTexCoords = [5]Vec2(f32){
    Vec2(f32).init(0, 0),
    Vec2(f32).init(0, 1),
    Vec2(f32).init(1, 1),
    Vec2(f32).init(1, 0),
    Vec2(f32).init(0, 0),
};
