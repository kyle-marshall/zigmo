const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

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
    is_freed: bool,

    const Self = @This();
    fn checkFanout(self: *Self, gate_id: GateId) bool {
        for (self.fanout.items) |id| {
            if (gate_id == id) return true;
        }
        return false;
    }

    fn debugPrint(self: *Self) void {
        std.debug.print(
            "id: {}, value: {}, fanout: {any}, ext. signal: {}, is_input: {}, is_undefined: {}, is_freed: {}\n",
            .{ self.id, self.value, self.fanout.items, self.external_signal, self.is_input, self.is_undefined, self.is_freed },
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
    outputs: ArrayList(NetId),
    // we avoid checking if gate queue already contains gate for now
    is_stale: bool,
};

const CircuitSimulatorEvent = struct {
    net_id: usize,
    value: LogicValue,
};

pub const CircuitSimulator = struct {
    const Self = @This();

    // circuit fun
    net_table: ArrayList(NetTableEntry),
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
            .net_table = ArrayList(NetTableEntry).init(allocator),
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
        for (self.net_table.items) |*net| {
            net.debugPrint();
        }
    }

    pub inline fn getValue(self: *Self, net_id: NetId) LogicValue {
        return self.net_table.items[net_id].value;
    }

    pub inline fn updateValue(self: *Self, net_id: NetId, value: LogicValue) void {
        var net = &(self.net_table.items[net_id]);
        net.value = value;
        net.is_undefined = false;

        std.debug.assert(!self.net_table.items[net_id].is_undefined);
        std.log.info("updated {} to {}", .{ net_id, value });
    }

    pub fn readInputs(self: *Self) !void {
        for (self.external_inputs.items, 0..) |input_id, i| {
            const input = self.net_table.items[input_id];
            if (input.is_undefined or input.external_signal != input.value) {
                if (input.is_undefined) {
                    std.log.info("undefined {}", .{input_id});
                } else {
                    std.log.info("{} != {}", .{ input.external_signal, input.value });
                }
                try self.createEvent(i, input.external_signal);
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
        return self.net_table.items[net_id].fanout;
    }

    pub inline fn simulateGate(self: *Self, gate_id: GateId) LogicValue {
        var gate = &self.gate_table.items[gate_id];
        return gate.simulate(self, gate);
    }

    pub fn processGates(self: *Self) !void {
        for (self.gate_queue.items) |gate_id| {
            const out_value = self.simulateGate(gate_id);
            var gate = &self.gate_table.items[gate_id];
            if (!gate.is_stale) continue;
            gate.is_stale = false;
            for (gate.outputs.items) |out_id| {
                const currValue = self.getValue(out_id);
                if (out_value != currValue) {
                    try self.createEvent(out_id, out_value);
                }
            }
        }
        self.event_queue.clearAndFree();
    }

    pub fn flushIntermediateOutput(self: *Self) void {
        for (self.event_queue.items) |*event| {
            self.updateValue(event.net_id, event.value);
        }
        self.event_queue.clearRetainingCapacity();
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

    pub fn addNet(self: *Self, is_external_input: bool) !NetId {
        const net_id = self.net_table.items.len;
        std.log.info("initializing net {d} ({})", .{ net_id, is_external_input });
        try self.net_table.append(NetTableEntry{
            .id = net_id,
            .value = false,
            .external_signal = false,
            .fanout = ArrayList(GateId).init(self.allocator),
            .is_undefined = true,
            .is_input = is_external_input,
            .is_freed = false,
        });
        if (is_external_input) {
            try self.external_inputs.append(net_id);
        }
        return net_id;
    }

    pub fn createObjectTag(self: *Self, variant: ObjectVariant, index: usize) !usize {
        const tag_index = self.obj_tags.items.len;
        try self.obj_tags.append(ObjectTag{
            .variant = variant,
            .index = index,
        });
        return tag_index;
    }

    pub inline fn free_net(self: *Self, net_id: NetId) !void {
        std.log.info("freeing net {}", .{net_id});
        var net = &self.net_table.items[net_id];
        net.is_freed = true;
        net.fanout.deinit();
        try self.free_net_ids.append(net_id);
    }

    /// net b will merge with net a (all previous references to net b will now refer to net a)
    pub fn merge_nets(self: *Self, net_a_id: NetId, net_b_id: NetId) !void {
        std.log.info("merge_nets {} and {}", .{ net_a_id, net_b_id });
        var net_a = &self.net_table.items[net_a_id];
        var net_b = &self.net_table.items[net_a_id];
        for (self.gate_table.items) |*gate| {
            for (gate.outputs.items, 0..) |out_id, index| {
                if (out_id == net_b_id) {
                    gate.outputs.items[index] = net_a_id;
                }
            }
        }
        for (net_b.fanout.items) |gate_id| {
            if (!net_a.checkFanout(gate_id)) {
                try net_a.fanout.append(gate_id);
            }
        }
        try self.free_net(net_b_id);
    }
};
