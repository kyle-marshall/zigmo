const std = @import("std");

pub const Fooer0VTable = struct {
    foo: *const fn (obj_ptr: usize) anyerror!u32,
    oof: *const fn (obj_ptr: usize) anyerror!void,
    const Self = @This();
    pub fn init(comptime T: type) Self {
        return Self{
            .foo = &T.foo,
            .oof = &T.oof,
        };
    }
};

pub const Fooer0 = struct {
    obj_ptr: usize,
    v_table: Fooer0VTable,
    const Self = @This();
    pub fn bind(obj_ptr: anytype, v_table: Fooer0VTable) Self {
        return Self{
            .obj_ptr = @ptrToInt(obj_ptr),
            .v_table = v_table,
        };
    }
    pub fn foo(self: *Self) anyerror!u32 {
        return self.v_table.foo(self.obj_ptr);
    }
    pub fn oof(self: *Self) anyerror!void {
        return self.v_table.oof(self.obj_ptr);
    }
};

const A0 = struct {
    count: u32 = 0,
    const Self = @This();

    const fooer_v_table = Fooer0VTable.init(Self);

    fn foo(hdl: usize) anyerror!u32 {
        var self = @intToPtr(*Self, hdl);
        const c = self.count;
        self.count += 1;
        return c;
    }

    fn oof(hdl: usize) anyerror!void {
        var self = @intToPtr(*Self, hdl);
        std.debug.print("OW!({d})\n", .{self.count});
    }

    pub fn fooer(self: *Self) Fooer0 {
        return Fooer0.bind(self, Self.fooer_v_table);
    }
};

const B0 = struct {
    on: bool = false,
    const Self = @This();
    pub fn foo(self_: usize) anyerror!u32 {
        var self = @intToPtr(*Self, self_);
        self.on = !self.on;
        return @as(u32, @boolToInt(self.on));
    }
    fn oof(self_: usize) anyerror!void {
        var self = @intToPtr(*Self, self_);
        std.debug.print("{any}\n", .{self.on});
    }
};

pub fn Fooer1VTable(comptime Context: type) type {
    return struct {
        foo: *const fn (ctx: *Context) anyerror!u32,
        oof: *const fn (ctx: *Context) anyerror!void,
        const Self = @This();
        pub fn init(comptime T: type) Self {
            return Self{
                .foo = &T.foo,
                .oof = &T.oof,
            };
        }
    };
}

pub fn Fooer1(comptime Context: type) type {
    return struct {
        obj_ptr: *Context,

        const Self = @This();
        const v_table = Fooer1VTable(Context).init(Context);

        pub fn foo(self: *Self) anyerror!u32 {
            return Self.v_table.foo(self.obj_ptr);
        }
        pub fn oof(self: *Self) anyerror!void {
            return Self.v_table.oof(self.obj_ptr);
        }
    };
}

const A1 = struct {
    count: u32 = 0,
    const Self = @This();

    fn foo(self: *Self) anyerror!u32 {
        const c = self.count;
        self.count += 1;
        return c;
    }

    fn oof(self: *Self) anyerror!void {
        std.debug.print("OW!({d})\n", .{self.count});
    }

    const Fooer = Fooer1(Self);

    pub fn fooer(self: *Self) Fooer {
        return Fooer{ .obj_ptr = self };
    }
};

const B1 = struct {
    on: bool = false,
    const Self = @This();
    fn foo(self: *Self) anyerror!u32 {
        self.on = !self.on;
        return @as(u32, @boolToInt(self.on));
    }
    fn oof(self: *Self) anyerror!void {
        std.debug.print("{any}\n", .{self.on});
    }
    const Fooer = Fooer1(Self);
    pub fn fooer(self: *Self) Fooer {
        return Fooer{ .obj_ptr = self };
    }
};

const Thing1 = union(enum) { a1: Fooer1(A1), b1: Fooer1(B1) };

pub fn test0() !void {
    var obj_tables = [_]Fooer0VTable{
        A0.fooer_v_table,
        Fooer0VTable.init(B0),
    };

    var a0 = A0{};
    var b0 = B0{};

    for (0..5) |_| {
        var x = try obj_tables[0].foo(@ptrToInt(&a0));
        std.debug.print("{d}\n", .{x});
        try obj_tables[0].oof(@ptrToInt(&a0));

        var y = try obj_tables[1].foo(@ptrToInt(&b0));
        std.debug.print("{d}\n", .{y});
        try obj_tables[1].oof(@ptrToInt(&b0));
    }

    var a1 = a0.fooer();
    try a1.oof();

    var b1 = Fooer0.bind(&b0, obj_tables[1]);
    try b1.oof();

    var apple = A1{ .count = 99 };
    var apple_fooer = apple.fooer();
    var apple_foo = try apple_fooer.foo();
    std.debug.print("{d}\n", .{apple_foo});
    try apple_fooer.oof();

    var baba = B1{ .on = true };
    var baba_fooer = baba.fooer();
    var baba_foo = try baba_fooer.foo();
    std.debug.print("{d}\n", .{baba_foo});
    try baba_fooer.oof();

    // var t0 = Thing1{ .a1 = apple_fooer };
    // var t1 = Thing1{ .b1 = baba_fooer };

    // var fooers = [2]Fooer1(Thing1){
    //     t0.a1,
    //     t1.b1,
    // };

    // _ = fooers;
}

pub fn doTests() !void {
    try test0();
}
