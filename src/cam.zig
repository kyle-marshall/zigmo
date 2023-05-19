const std = @import("std");
const math = @import("root").math;
const Vec2 = math.Vec2;
const Mat3 = math.Mat3;
const Rect = math.geo.Rect;

pub fn Cam2(comptime T: type) type {
    return struct {
        const Self = @This();
        screen_size: Vec2(T),
        transform: Mat3(T),
        inverse_transform: ?Mat3(T),
        max_smooth_speed: T,
        min_smooth_distance: T,
        curr_scale: T,
        visible_rect: Rect(T),

        pub fn init(screen_size: Vec2(T), transform: Mat3(T)) Self {
            return Self{
                .screen_size = screen_size,
                .transform = transform,
                .inverse_transform = transform.inverse(),
                .max_smooth_speed = 100,
                .min_smooth_distance = 1,
                .curr_scale = 1,
                .visible_rect = Rect(T).init(Vec2(T).zero, screen_size),
            };
        }
        pub inline fn worldToScreen(self: Self, world_point: Vec2(T)) Vec2(T) {
            return self.transform.vec2Mul(world_point);
        }
        pub inline fn screenToWorld(self: Self, screen_point: Vec2(T)) Vec2(T) {
            const inverse_transform = self.inverse_transform orelse unreachable;
            return inverse_transform.vec2Mul(screen_point);
        }
        inline fn applyTransformBase(self: *Self, transform: Mat3(T)) void {
            self.transform = self.transform.leftMul(transform);
            self.inverse_transform = self.transform.inverse();
            self.visible_rect = self.getVisibleRect();
        }
        pub inline fn applyTransform(self: *Self, transform: Mat3(T)) void {
            self.applyTransformBase(transform);
            self.curr_scale = self.getCurrentScale();
        }
        fn getVisibleRect(self: Self) Rect(T) {
            const inverse_transform = self.inverse_transform orelse unreachable;
            const screen_origin = Vec2(T).zero;
            const screen_origin_w = inverse_transform.vec2Mul(screen_origin);
            const bot_right = inverse_transform.vec2Mul(self.screen_size);
            const screen_size_w = bot_right.sub(screen_origin_w);
            return Rect(T).init(screen_origin_w, screen_size_w);
        }
        pub fn getCurrentScale(self: Self) T {
            const inverse_transform = self.inverse_transform orelse unreachable;
            const screen_origin = Vec2(T).zero;
            const screen_origin_w = inverse_transform.vec2Mul(screen_origin);
            const bot_right = inverse_transform.vec2Mul(Vec2(T).X);
            const screen_size_w = bot_right.sub(screen_origin_w);
            return 1 / screen_size_w.v[0];
        }
        inline fn getCenterOnTranslationVector(self: *Self, world_point: Vec2(T)) Vec2(T) {
            const screen_point = self.worldToScreen(world_point);
            const screen_center = self.screen_size.divScalar(2);
            return screen_center.sub(screen_point);
        }
        pub fn centerOnInstant(self: *Self, world_point: Vec2(T)) void {
            const delta = self.getCenterOnTranslationVector(world_point);
            const transform = Mat3(T).txTranslate(delta.v[0], delta.v[1]);
            self.applyTransformBase(transform);
        }
        pub fn centerOnSmooth(self: *Self, world_point: Vec2(T), dt: T) void {
            var delta = self.getCenterOnTranslationVector(world_point);
            const distance = delta.mag();
            if (distance > self.min_smooth_distance) {
                const target_speed = @min(self.max_smooth_speed * self.curr_scale, distance * self.curr_scale);
                delta = delta.divScalar(distance).mulScalar(target_speed * dt);
            }
            const transform = Mat3(T).txTranslate(delta.v[0], delta.v[1]);
            self.applyTransformBase(transform);
        }
    };
}
