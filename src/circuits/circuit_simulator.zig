const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const ObjectStore = @import("root").ObjectStore;

pub const LogicValue = bool;
pub const NetId = usize;
pub const GateId = usize;

pub const NetTableEntry = struct {
    id: NetId,
    value: LogicValue,
    fanout: ArrayList(NetId),
    external_signal: LogicValue,
    is_input: bool,
    is_undefined: bool,

    const Self = @This();
    fn checkFanout(self: *Self, gate_id: GateId) bool {
        for (self.fanout.items) |id| {
            if (gate_id == id) return true;
        }
        return false;
    }

    fn debugPrint(self: *Self) void {
        std.debug.print(
            "{{ id: {}, value: {}, fanout: {any}, ext. signal: {}, is_input: {}, is_undefined: {} }}\n",
            .{ self.id, self.value, self.fanout.items, self.external_signal, self.is_input, self.is_undefined },
        );
    }
};

pub const ObjectVariant = enum { pin, component };

pub const ObjectTag = struct {
    variant: ObjectVariant,
    index: usize,
};

pub const SimulateGateFn = *const fn (simulator: *CircuitSimulator, gate_ptr: *GateTableEntry) LogicValue;
pub const GateTableEntry = struct {
    id: GateId,
    simulate: SimulateGateFn,
    inputs: ArrayList(NetId),
    output: NetId,
    // we avoid checking if gate queue already contains gate for now
    is_stale: bool,
    const Self = @This();
    fn debugPrint(self: *Self) void {
        std.debug.print(
            "{{ id: {}, inputs: {any}, output: {} }}\n",
            .{ self.id, self.inputs.items, self.output },
        );
    }
};

pub const GateVariant = enum {
    AND,
    OR,
    NOT,
    XOR,
    NAND,
    NOR,
    XNOR,
};

pub const GateFactory = struct {
    const Self = @This();
    pub fn AND(csim: *CircuitSimulator, gate_ptr: *GateTableEntry) LogicValue {
        if (gate_ptr.inputs.items.len == 0) {
            return false;
        }
        for (gate_ptr.inputs.items) |net_id| {
            if (!csim.getValue(net_id)) {
                return false;
            }
        }
        return true;
    }

    pub fn OR(csim: *CircuitSimulator, gate_ptr: *GateTableEntry) LogicValue {
        if (gate_ptr.inputs.items.len == 0) {
            return false;
        }
        for (gate_ptr.inputs.items) |net_id| {
            if (csim.getValue(net_id)) {
                return true;
            }
        }
        return false;
    }

    pub fn XOR(csim: *CircuitSimulator, gate_ptr: *GateTableEntry) LogicValue {
        if (gate_ptr.inputs.items.len != 2) {
            return false;
        }
        const a = csim.getValue(gate_ptr.inputs.items[0]);
        const b = csim.getValue(gate_ptr.inputs.items[1]);
        return (a != b);
    }

    pub fn NOT(csim: *CircuitSimulator, gate_ptr: *GateTableEntry) LogicValue {
        if (gate_ptr.inputs.items.len != 1) {
            return false;
        }
        return !csim.getValue(gate_ptr.inputs.items[0]);
    }

    pub fn NAND(csim: *CircuitSimulator, gate_ptr: *GateTableEntry) LogicValue {
        return !Self.AND(csim, gate_ptr);
    }

    pub fn NOR(csim: *CircuitSimulator, gate_ptr: *GateTableEntry) LogicValue {
        return !Self.OR(csim, gate_ptr);
    }

    pub fn XNOR(csim: *CircuitSimulator, gate_ptr: *GateTableEntry) LogicValue {
        return !Self.XOR(csim, gate_ptr);
    }

    pub fn getSimulateFn(comptime variant: GateVariant) SimulateGateFn {
        return switch (variant) {
            .AND => Self.AND,
            .OR => Self.OR,
            .NOT => Self.NOT,
            .XOR => Self.XOR,
            .NAND => Self.NAND,
            .NOR => Self.NOR,
            .XNOR => Self.XNOR,
        };
    }

    pub fn createGate(allocator: Allocator, id: GateId, simulate: SimulateGateFn) GateTableEntry {
        return GateTableEntry{
            .id = id,
            .simulate = simulate,
            .inputs = ArrayList(NetId).init(allocator),
            .output = 0,
            .is_stale = false,
        };
    }
};

const CircuitSimulatorEvent = struct {
    net_id: usize,
    value: LogicValue,
};

pub const CircuitSimulator = struct {
    const Self = @This();

    // circuit fun
    net_table: ObjectStore(NetTableEntry),
    gate_table: ArrayList(GateTableEntry),
    event_queue: ArrayList(CircuitSimulatorEvent),
    gate_queue: ArrayList(GateId),
    external_inputs: ArrayList(NetId),

    // world action state
    free_net_ids: ArrayList(NetId),

    // resources
    allocator: Allocator,

    pub fn init(allocator: Allocator) !Self {
        var obj = Self{
            .allocator = allocator,
            .net_table = ObjectStore(NetTableEntry).init(allocator),
            .gate_table = ArrayList(GateTableEntry).init(allocator),
            .event_queue = ArrayList(CircuitSimulatorEvent).init(allocator),
            .gate_queue = ArrayList(GateId).init(allocator),
            .external_inputs = ArrayList(NetId).init(allocator),
            .free_net_ids = ArrayList(NetId).init(allocator),
        };
        return obj;
    }

    pub fn deinit(self: *Self) void {
        self.net_table.deinit();
        self.event_queue.deinit();
        self.gate_queue.deinit();
    }

    pub fn printNetTable(self: *Self) void {
        std.debug.print("[NET TABLE]\n", .{});
        var iter = self.net_table.iterator();
        while (iter.next()) |net| {
            net.debugPrint();
        }
        std.debug.print("primary inputs: {any}\n", .{self.external_inputs.items});
    }
    pub fn printGateTable(self: *Self) void {
        std.debug.print("[GATE TABLE]\n", .{});
        for (self.gate_table.items) |*gate| {
            gate.debugPrint();
        }
    }

    pub inline fn getValue(self: *Self, net_id: NetId) LogicValue {
        return self.net_table.getPtr(net_id).value;
    }

    pub inline fn updateValue(self: *Self, net_id: NetId, value: LogicValue) void {
        var net = self.net_table.getPtr(net_id);
        net.value = value;
        net.is_undefined = false;
        std.log.info("updated net {} to {}", .{ net_id, value });
    }

    pub fn readInputs(self: *Self) !void {
        for (self.external_inputs.items) |input_id| {
            const input_net = self.net_table.getPtr(input_id);
            if (input_net.is_undefined or input_net.external_signal != input_net.value) {
                if (input_net.is_undefined) {
                    std.log.info("undefined {}", .{input_id});
                } else {
                    std.log.info("{} != {}", .{ input_net.external_signal, input_net.value });
                }
                try self.createEvent(input_net.id, input_net.external_signal);
            }
        }
    }

    pub inline fn createEvent(self: *Self, net_id: usize, value: LogicValue) !void {
        std.log.info("[EVENT {d} {}]", .{ net_id, value });
        try self.event_queue.append(CircuitSimulatorEvent{
            .net_id = net_id,
            .value = value,
        });
    }

    pub inline fn invalidateGate(self: *Self, gate_id: GateId) void {
        var gate = &self.gate_table.items[gate_id];
        gate.is_stale = true;
    }

    pub fn simulate(self: *Self) !void {
        try self.readInputs();
        while (self.event_queue.items.len > 0) {
            try self.processEvents();
            self.flushIntermediateOutput();
            if (self.gate_queue.items.len > 0) {
                try self.processGates();
            }
        }
    }

    pub fn processEvents(self: *Self) !void {
        for (self.event_queue.items) |*event| {
            for (self.getFanout(event.net_id).items) |gate_id| {
                try self.gate_queue.append(gate_id);
                self.invalidateGate(gate_id);
            }
        }
        std.log.info("process events queued {} gate updates", .{self.gate_queue.items.len});
    }

    pub inline fn getFanout(self: *Self, net_id: NetId) ArrayList(GateId) {
        const net = self.net_table.getPtr(net_id);
        return net.fanout;
    }

    pub inline fn simulateGate(self: *Self, gate_id: GateId) LogicValue {
        var gate = &self.gate_table.items[gate_id];
        return gate.simulate(self, gate);
    }

    /// Simulate all gates in the gate queue.
    /// If gate simulation leads to output change, queue an event.
    pub fn processGates(self: *Self) !void {
        for (self.gate_queue.items) |gate_id| {
            const out_value = self.simulateGate(gate_id);
            const inputs = self.gate_table.items[gate_id].inputs.items;
            std.debug.print("gate {} ({any}) -> {}\n", .{ gate_id, inputs, out_value });
            var gate = &self.gate_table.items[gate_id];
            // is_stale was added because gates MAY be added multiple times during processEvents
            // due do me skipping the pseudocode lookup of whether gate is already in queue
            if (!gate.is_stale) continue;
            gate.is_stale = false;
            const currValue = self.getValue(gate.output);
            if (out_value != currValue) {
                try self.createEvent(gate.output, out_value);
            }
        }
        self.gate_queue.clearAndFree();
    }

    /// read values from event queue, write them to net table
    pub fn flushIntermediateOutput(self: *Self) void {
        for (self.event_queue.items) |*event| {
            self.updateValue(event.net_id, event.value);
        }
        self.event_queue.clearRetainingCapacity();
    }

    pub fn addNet(self: *Self, is_external_input: bool) !NetId {
        const id = try self.net_table.store(NetTableEntry{
            .id = undefined,
            .value = false,
            .external_signal = false,
            .fanout = ArrayList(GateId).init(self.allocator),
            .is_undefined = true,
            .is_input = is_external_input,
        });
        var net = self.net_table.getPtr(id);
        net.id = id;
        if (is_external_input) {
            try self.external_inputs.append(id);
        }
        std.log.info("initialized net {d} (is_external_input = {})", .{ id, is_external_input });
        return id;
    }

    pub fn createObjectTag(self: *Self, variant: ObjectVariant, index: usize) !usize {
        const tag_index = self.obj_tags.items.len;
        try self.obj_tags.append(ObjectTag{
            .variant = variant,
            .index = index,
        });
        return tag_index;
    }

    pub inline fn freeNet(self: *Self, net_id: NetId) !void {
        std.log.info("freeNet {}", .{net_id});
        var net = self.net_table.getPtr(net_id);
        net.fanout.deinit();
        try self.net_table.remove(net_id);
    }

    /// net b will merge with net a (all previous references to net b will now refer to net a)
    pub fn mergeNets(self: *Self, net_a_id: NetId, net_b_id: NetId) !void {
        std.log.info("mergeNets {} <-- {}", .{ net_a_id, net_b_id });
        var net_a = self.net_table.getPtr(net_a_id);
        var net_b = self.net_table.getPtr(net_b_id);
        for (self.external_inputs.items, 0..) |input_id, idx| {
            if (input_id == net_b_id) {
                self.external_inputs.items[idx] = net_a_id;
                net_a.is_input = true;
            }
        }
        for (self.gate_table.items) |*gate| {
            if (gate.output == net_b_id) {
                gate.output = net_a_id;
            }
            for (gate.inputs.items, 0..) |input, i| {
                if (input == net_b_id) {
                    gate.inputs.items[i] = net_a_id;
                }
            }
        }
        for (net_b.fanout.items) |gate_id| {
            if (!net_a.checkFanout(gate_id)) {
                try net_a.fanout.append(gate_id);
            }
        }
        try self.freeNet(net_b_id);
    }
};

pub fn circuitTest() !void {
    const allocator = std.heap.page_allocator;
    std.log.info("circuitTest initiated", .{});
    var csim = try CircuitSimulator.init(allocator);

    var n0 = try csim.addNet(true);
    var n1 = try csim.addNet(true);
    var n2 = try csim.addNet(false);

    var net0 = csim.net_table.getPtr(n0);
    var net1 = csim.net_table.getPtr(n1);
    // var net2 = csim.net_table.getPtr(n2);

    net0.is_input = true;
    net1.is_input = true;

    var g0: usize = 0;
    try csim.gate_table.append(GateFactory.createGate(
        allocator,
        0,
        GateFactory.AND,
    ));
    try net0.fanout.append(g0);
    try net1.fanout.append(g0);

    var gate0 = &csim.gate_table.items[g0];
    try gate0.inputs.append(n0);
    try gate0.inputs.append(n1);
    gate0.output = n2;

    const InputVec = [2]LogicValue;
    var input_vecs = ArrayList(InputVec).init(allocator);
    try input_vecs.append(.{ true, true });
    try input_vecs.append(.{ true, false });
    // try input_vecs.append(.{ false, false });
    // try input_vecs.append(.{ false, true });
    // try input_vecs.append(.{ true, true });

    const frames_per_input_change = 3;

    std.debug.print("First call to simulate", .{});
    try csim.simulate();
    csim.printNetTable();
    std.debug.print("\n", .{});
    csim.printGateTable();
    std.debug.print("\n", .{});

    for (input_vecs.items, 0..) |v, v_i| {
        for (0..frames_per_input_change) |frame| {
            std.debug.print("[Frame {}] {any}\n", .{ frame + v_i * frames_per_input_change, v });

            // csim.updateValue(n0, v[0]); <- this doesn't work bc n0/n1 are external inputs
            // csim.updateValue(n1, v[1]);
            net0.external_signal = v[0];
            net1.external_signal = v[1];

            try csim.simulate();
            csim.printNetTable();
            std.debug.print("\n", .{});
            csim.printGateTable();
            std.debug.print("\n", .{});
        }
    }

    try net0.fanout.append(g0);
    try net1.fanout.append(g0);
}
