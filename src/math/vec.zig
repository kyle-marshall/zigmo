const std = @import("std");
const RaylibVector2 = @import("root").raylib.Vector2;

fn VecFunctions(comptime VecT: type, comptime N: usize, comptime NumT: type) type {
    return struct {
        pub inline fn fromVector(vector: @Vector(N, NumT)) VecT {
            return VecT{ .v = vector };
        }

        pub inline fn clone(self: VecT) VecT {
            return VecT{ .v = self.v };
        }

        pub inline fn add(a: VecT, b: VecT) VecT {
            return VecT{ .v = a.v + b.v };
        }

        pub inline fn addInPlace(a: *VecT, b: VecT) *VecT {
            a.v += b.v;
            return a;
        }

        pub inline fn addScalar(a: VecT, b: NumT) VecT {
            return VecT{ .v = a.v + @splat(2, b) };
        }

        pub inline fn sub(a: VecT, b: VecT) VecT {
            return VecT{ .v = a.v - b.v };
        }

        pub inline fn subInPlace(a: *VecT, b: VecT) *VecT {
            a.v -= b.v;
            return a;
        }

        pub inline fn subScalar(a: VecT, b: NumT) VecT {
            return VecT{ .v = a.v - @splat(2, b) };
        }

        pub inline fn mul(a: VecT, b: VecT) VecT {
            return VecT{ .v = a.v * b.v };
        }

        pub inline fn mulInPlace(a: *VecT, b: VecT) *VecT {
            a.v *= b.v;
            return a;
        }

        pub inline fn mulScalar(self: VecT, k: NumT) VecT {
            return VecT{ .v = self.v * @splat(2, k) };
        }

        pub inline fn mulScalarInPlace(self: *VecT, k: NumT) *VecT {
            self.v *= @splat(2, k);
            return self;
        }

        pub inline fn div(a: VecT, b: VecT) VecT {
            return VecT{ .v = a.v / b.v };
        }

        pub inline fn divInPlace(a: *VecT, b: VecT) *VecT {
            a.v /= b.v;
            return a;
        }

        pub inline fn divScalar(a: VecT, b: NumT) VecT {
            return VecT{ .v = a.v / @splat(2, b) };
        }

        pub inline fn dot(a: VecT, b: VecT) NumT {
            return @reduce(.Add, a.v * b.v);
        }

        pub inline fn floor(self: VecT) VecT {
            return VecT{ .v = @floor(self.v) };
        }

        pub inline fn floorInPlace(self: *VecT) *VecT {
            self.v = @floor(self.v);
            return self;
        }

        pub inline fn ceil(self: VecT) VecT {
            return VecT{ .v = @ceil(self.v) };
        }

        pub inline fn ceilInPlace(self: *VecT) *VecT {
            self.v = @ceil(self.v);
            return self;
        }

        pub inline fn mag(self: VecT) NumT {
            return @sqrt(@reduce(.Add, self.v * self.v));
        }

        pub inline fn fill(value: NumT) VecT {
            return VecT{ .v = @splat(N, value) };
        }

        pub inline fn distanceBetween(a: VecT, b: VecT) NumT {
            const diff = a.v - b.v;
            return @sqrt(@reduce(.Add, diff * diff));
        }

        pub fn debugPrint(self: VecT) void {
            std.debug.print("{s}(", .{@typeName(VecT)});
            for (0..N) |i| {
                const v = self.v[i];
                std.debug.print("{d}", .{v});
                if (i < N - 1) std.debug.print(", ", .{});
            }
            std.debug.print(")\n", .{});
        }
    };
}

pub fn Vec2(comptime T: type) type {
    return struct {
        v: @Vector(2, T),
        const Self = @This();
        pub usingnamespace VecFunctions(Self, 2, T);

        pub const zero = Self.init(0, 0);
        pub const one = Self.init(1, 1);

        pub const X = Self.init(1, 0);
        pub const Y = Self.init(0, 1);

        pub inline fn equals(self: Self, other: Self) bool {
            return self.v[0] == other.v[0] and self.v[1] == other.v[1];
        }

        pub inline fn init(x: T, y: T) Self {
            return Self{ .v = .{ x, y } };
        }

        pub inline fn max(self: Self) T {
            return @max(self.v[0], self.v[1]);
        }

        pub inline fn map(self: Self, comptime TP: type, tx: fn (value: T, index: usize) TP) Vec2(TP) {
            return Vec2(TP).init(tx(self.v[0], 0), tx(self.v[1], 1));
        }

        pub inline fn floatToInt(self: Self, comptime IntT: type) Vec2(IntT) {
            const map_fn = (struct {
                pub fn f(value: T, index: usize) IntT {
                    _ = index;
                    return @floatToInt(IntT, value);
                }
            }).f;
            return self.map(IntT, map_fn);
        }

        pub inline fn intCast(self: Self, comptime IntT: type) Vec2(IntT) {
            const map_fn = (struct {
                pub fn f(value: T, index: usize) IntT {
                    _ = index;
                    return @intCast(IntT, value);
                }
            }).f;
            return self.map(IntT, map_fn);
        }

        pub inline fn toRaylibVector2(self: Self) RaylibVector2 {
            return RaylibVector2{ .x = self.v[0], .y = self.v[1] };
        }

        pub inline fn fromRaylibVector2(v: RaylibVector2) Self {
            return Self.init(v.x, v.y);
        }
    };
}

pub fn Vec3(comptime T: type) type {
    return struct {
        v: @Vector(3, T),
        const Self = @This();
        pub usingnamespace VecFunctions(Self, 3, T);
        pub const zero = Self.init(0, 0);
        pub inline fn init(x: T, y: T, z: T) Self {
            return Self{ .v = .{ x, y, z } };
        }
    };
}
