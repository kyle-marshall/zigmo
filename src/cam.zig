const std = @import("std");
const root = @import("root");
const raylib = root.raylib;
const math = root.math;
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

        pub fn worldToScreen(self: Self, world_point: Vec2(T)) Vec2(T) {
            return self.transform.vec2Mul(world_point);
        }

        pub fn screenToWorld(self: Self, screen_point: Vec2(T)) Vec2(T) {
            const inverse_transform = self.inverse_transform orelse unreachable;
            return inverse_transform.vec2Mul(screen_point);
        }

        pub fn worldToScreenRect(self: Self, world_rect: Rect(T)) Rect(T) {
            const top_left = self.worldToScreen(world_rect.origin);
            const size = world_rect.size.mulScalar(self.curr_scale);
            return Rect(T).init(top_left, size);
        }

        pub fn applyTransformBase(self: *Self, transform: Mat3(T)) void {
            self.transform = self.transform.leftMul(transform);
            self.inverse_transform = self.transform.inverse();
            self.visible_rect = self.getVisibleRect();
        }

        pub fn applyTransform(self: *Self, transform: Mat3(T)) void {
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

        pub fn getCenterOnTranslationVector(self: *Self, world_point: Vec2(T)) Vec2(T) {
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

pub fn Cam2Controller(comptime T: type) type {
    return struct {
        const Self = @This();
        cam: *Cam2(T),
        pan_speed: T = 10,
        zoom_speed: T = 1.1,
        is_panning: bool = false,
        pan_start: Vec2(T) = Vec2(T).zero,
        prev_is_middle_mouse_down: bool = false,

        pub fn init(cam: *Cam2(T)) Self {
            return Self{ .cam = cam };
        }

        pub fn panUpdate(self: *Self, screen_pos: Vec2(T)) void {
            if (self.is_panning) {
                const delta = screen_pos.sub(self.pan_start);
                self.cam.applyTransform(Mat3(T).txTranslate(delta.v[0], delta.v[1]));
                self.pan_start = screen_pos;
            }
        }

        pub fn update(self: *Self, dt: T) void {
            _ = dt;
            if (raylib.IsKeyDown(raylib.KEY_RIGHT)) {
                const tx = Mat3(T).txTranslate(-self.pan_speed, 0);
                self.cam.applyTransform(tx);
            }
            if (raylib.IsKeyDown(raylib.KEY_LEFT)) {
                const tx = Mat3(T).txTranslate(self.pan_speed, 0);
                self.cam.applyTransform(tx);
            }
            if (raylib.IsKeyDown(raylib.KEY_UP)) {
                const tx = Mat3(T).txTranslate(0, self.pan_speed);
                self.cam.applyTransform(tx);
            }
            if (raylib.IsKeyDown(raylib.KEY_DOWN)) {
                const tx = Mat3(T).txTranslate(0, -self.pan_speed);
                self.cam.applyTransform(tx);
            }
            const wheel_move = raylib.GetMouseWheelMove();
            if (wheel_move > 0) {
                const tx = Mat3(T).txScale(self.zoom_speed, self.zoom_speed);
                self.cam.applyTransform(tx);
            } else if (wheel_move < 0) {
                const s = 1.0 / self.zoom_speed;
                const tx = Mat3(T).txScale(s, s);
                self.cam.applyTransform(tx);
            }

            const mouse_pos = Vec2(T).fromRaylibVector2(raylib.GetMousePosition());
            self.panUpdate(mouse_pos);

            const is_middle_mouse_down = raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_MIDDLE);
            switch (is_middle_mouse_down) {
                true => if (!self.prev_is_middle_mouse_down) {
                    self.is_panning = true;
                    self.pan_start = mouse_pos;
                },
                false => if (self.prev_is_middle_mouse_down) {
                    self.is_panning = false;
                },
            }
            self.prev_is_middle_mouse_down = is_middle_mouse_down;
        }
    };
}
