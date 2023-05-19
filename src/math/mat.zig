const std = @import("std");
const math = @import("math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;

pub fn Mat2(comptime T: type) type {
    return struct {
        c: [2]ColumnVec,

        const V2 = @Vector(2, T);
        pub const ColumnVec = V2;
        pub const RowVec = V2;
        const Self = @This();

        pub const identity = Self.fromColumns(
            ColumnVec{ 1, 0 },
            ColumnVec{ 0, 1 },
        );

        inline fn _row(self: Self, r: usize) RowVec {
            return RowVec{ self.c[0][r], self.c[1][r] };
        }

        pub inline fn fromColumns(c0: ColumnVec, c1: ColumnVec) Self {
            return Self{ .c = .{ c0, c1 } };
        }

        pub inline fn det(self: Self) T {
            return self.c[0][0] * self.c[1][1] - self.c[0][1] * self.c[1][0];
        }

        pub inline fn vec2Mul(self: Self, vec: Vec2(T)) Vec2(T) {
            const product =
                (self.c[0] * @splat(3, vec.v[0])) +
                (self.c[1] * @splat(3, vec.v[1]));
            return Vec2(T).init(product[0], product[1]);
        }

        pub inline fn mul(a: Self, b: Self) Self {
            const ra0 = a._row(0);
            const ra1 = a._row(1);
            const result = Self.init(
                ColumnVec{ @reduce(.Add, ra0 * b.c[0]), @reduce(.Add, ra1 * b.c[0]) },
                ColumnVec{ @reduce(.Add, ra0 * b.c[1]), @reduce(.Add, ra1 * b.c[1]) },
            );
            return result;
        }

        pub inline fn leftMul(a: Self, b: Self) Self {
            return b.mul(a);
        }

        pub fn debugPrint(self: Self) void {
            std.debug.print("[{s}]\n", .{@typeName(Self)});
            std.debug.print("c[0]: ", .{});
            Vec2(T).fromVector(self.c[0]).debugPrint();
            std.debug.print("c[1]: ", .{});
            Vec2(T).fromVector(self.c[1]).debugPrint();
        }
    };
}

pub fn Mat3(comptime T: type) type {
    return struct {
        c: [3]ColumnVec,

        const V3 = @Vector(3, T);
        pub const ColumnVec = V3;
        pub const RowVec = V3;
        const Self = @This();

        pub const identity = Self.fromColumns(
            ColumnVec{ 1, 0, 0 },
            ColumnVec{ 0, 1, 0 },
            ColumnVec{ 0, 0, 1 },
        );

        pub const sign = Self.fromColumns(
            ColumnVec{ 1, -1, 1 },
            ColumnVec{ -1, 1, -1 },
            ColumnVec{ 1, -1, 1 },
        );

        inline fn _row(self: Self, r: usize) RowVec {
            return RowVec{ self.c[0][r], self.c[1][r], self.c[2][r] };
        }

        pub inline fn fromColumns(c0: ColumnVec, c1: ColumnVec, c2: ColumnVec) Self {
            return Self{ .c = .{ c0, c1, c2 } };
        }

        pub inline fn transpose(self: Self) Self {
            return Self.fromColumns(self._row(0), self._row(1), self._row(2));
        }

        pub inline fn _getMinor(self: Self, col: usize, row: usize) Mat2(T) {
            const c0index = if (col == 0) 1 else 0;
            const c1index = if (col == 2) 1 else 2;
            const r0index = if (row == 0) 1 else 0;
            const r1index = if (row == 2) 1 else 2;
            return Mat2(T).fromColumns(
                @Vector(2, T){ self.c[c0index][r0index], self.c[c0index][r1index] },
                @Vector(2, T){ self.c[c1index][r0index], self.c[c1index][r1index] },
            );
        }

        pub inline fn getMinor(self: Self, col: usize, row: usize) T {
            return self._getMinor(col, row).det();
        }

        pub inline fn getMinorMatrix(self: Self) Self {
            return Self.fromColumns(
                ColumnVec{ self.getMinor(0, 0), self.getMinor(0, 1), self.getMinor(0, 2) },
                ColumnVec{ self.getMinor(1, 0), self.getMinor(1, 1), self.getMinor(1, 2) },
                ColumnVec{ self.getMinor(2, 0), self.getMinor(2, 1), self.getMinor(2, 2) },
            );
        }

        inline fn getCofactors(self: Self) Self {
            return self.getMinorMatrix().mulElems(Mat3(T).sign);
        }

        pub inline fn getAdjugate(self: Self) Self {
            return self.getCofactors().transpose();
        }

        pub inline fn det(self: Self) T {
            return self.c[0][0] * self.c[1][1] * self.c[2][2] +
                self.c[0][1] * self.c[1][2] * self.c[2][0] +
                self.c[0][2] * self.c[1][0] * self.c[2][1] -
                self.c[0][2] * self.c[1][1] * self.c[2][0] -
                self.c[0][1] * self.c[1][0] * self.c[2][2] -
                self.c[0][0] * self.c[1][2] * self.c[2][1];
        }

        pub inline fn inverse(self: Self) ?Self {
            const _det = self.det();
            if (_det == 0) return null;
            const adjugate = self.getAdjugate();
            return adjugate.mulScalar(1 / _det);
        }

        pub inline fn vec2Mul(self: Self, vec: Vec2(T)) Vec2(T) {
            const product =
                (self.c[0] * @splat(3, vec.v[0])) +
                (self.c[1] * @splat(3, vec.v[1])) +
                (self.c[2] * @splat(3, @as(T, 1)));
            return Vec2(T).init(product[0], product[1]);
        }

        pub inline fn mul(a: Self, b: Self) Self {
            const ra0 = a._row(0);
            const ra1 = a._row(1);
            const ra2 = a._row(2);
            const result = Self.fromColumns(
                ColumnVec{ @reduce(.Add, ra0 * b.c[0]), @reduce(.Add, ra1 * b.c[0]), @reduce(.Add, ra2 * b.c[0]) },
                ColumnVec{ @reduce(.Add, ra0 * b.c[1]), @reduce(.Add, ra1 * b.c[1]), @reduce(.Add, ra2 * b.c[1]) },
                ColumnVec{ @reduce(.Add, ra0 * b.c[2]), @reduce(.Add, ra1 * b.c[2]), @reduce(.Add, ra2 * b.c[2]) },
            );
            // a.debugPrint();
            // std.debug.print(" * ", .{});
            // b.debugPrint();
            // std.debug.print(" = ", .{});
            // result.debugPrint();
            return result;
        }

        pub inline fn mulScalar(self: Self, scalar: T) Self {
            const s = @splat(3, scalar);
            return Self.fromColumns(
                self.c[0] * s,
                self.c[1] * s,
                self.c[2] * s,
            );
        }

        pub inline fn mulElems(a: Self, b: Self) Self {
            return Self.fromColumns(a.c[0] * b.c[0], a.c[1] * b.c[1], a.c[2] * b.c[2]);
        }

        pub inline fn leftMul(a: Self, b: Self) Self {
            return b.mul(a);
        }

        pub inline fn txTranslate(x: T, y: T) Self {
            return Self.fromColumns(
                ColumnVec{ 1, 0, 0 },
                ColumnVec{ 0, 1, 0 },
                ColumnVec{ x, y, 1 },
            );
        }

        pub inline fn txRotate(theta: T) Self {
            return Self.fromColumns(
                ColumnVec{ std.math.cos(theta), std.math.sin(theta), 0 },
                ColumnVec{ -std.math.sin(theta), std.math.cos(theta), 0 },
                ColumnVec{ 0, 0, 1 },
            );
        }

        pub inline fn txScale(sx: T, sy: T) Self {
            return Self.fromColumns(
                ColumnVec{ sx, 0, 0 },
                ColumnVec{ 0, sy, 0 },
                ColumnVec{ 0, 0, 1 },
            );
        }

        pub fn debugPrint(self: Self) void {
            std.debug.print("[{s}]\n", .{@typeName(Self)});
            std.debug.print("c[0]: ", .{});
            Vec3(T).fromVector(self.c[0]).debugPrint();
            std.debug.print("c[1]: ", .{});
            Vec3(T).fromVector(self.c[1]).debugPrint();
            std.debug.print("c[2]: ", .{});
            Vec3(T).fromVector(self.c[2]).debugPrint();
        }
    };
}
