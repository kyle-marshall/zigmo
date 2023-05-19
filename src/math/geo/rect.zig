const std = @import("std");
const math = @import("root").math;
const Vec2 = math.Vec2;

pub fn Rect(comptime NumT: type) type {
    return struct {
        pub const epsf32 = 0.0001;
        const Self = @This();
        origin: Vec2(NumT),
        size: Vec2(NumT),

        pub inline fn init(origin: Vec2(NumT), size: Vec2(NumT)) Self {
            return Self{ .origin = origin, .size = size };
        }

        pub inline fn containsPoint(self: Self, point: Vec2(NumT)) bool {
            return @reduce(.And, point.v >= self.origin.v) and @reduce(.And, point.v < (self.origin.v + self.size.v));
        }

        pub inline fn clampPoint(self: Self, point: Vec2(NumT)) Vec2(NumT) {
            return Vec2(NumT).init(
                std.math.clamp(point.v[0], self.origin.v[0], self.origin.v[0] + self.size.v[0] - epsf32),
                std.math.clamp(point.v[1], self.origin.v[1], self.origin.v[1] + self.size.v[1] - epsf32),
            );
        }

        pub inline fn isExactlyMaxValueX(self: Self, x: NumT) bool {
            return self.origin.v[0] + self.size.v[0] - epsf32 == x;
        }

        pub inline fn isExactlyMaxValueY(self: Self, y: NumT) bool {
            return self.origin.v[1] + self.size.v[1] - epsf32 == y;
        }

        pub fn debugPrint(self: Self) void {
            std.debug.print("{s}({d}, {d}, {d}, {d})\n", .{ @typeName(Self), self.origin.v[0], self.origin.v[1], self.size.v[0], self.size.v[1] });
        }
    };
}
