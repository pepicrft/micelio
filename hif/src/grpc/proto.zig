const std = @import("std");

pub const WireType = enum(u3) {
    varint = 0,
    length_delimited = 2,
};

pub fn encodeVarint(writer: anytype, value: u64) !void {
    var v = value;
    while (v >= 0x80) {
        try writer.writeByte(@intCast((v & 0x7F) | 0x80));
        v >>= 7;
    }
    try writer.writeByte(@intCast(v));
}

pub fn encodeKey(writer: anytype, field_number: u32, wire_type: WireType) !void {
    const key: u64 = (@as(u64, field_number) << 3) | @intFromEnum(wire_type);
    try encodeVarint(writer, key);
}

pub fn encodeBytesField(writer: anytype, field_number: u32, value: []const u8) !void {
    try encodeKey(writer, field_number, .length_delimited);
    try encodeVarint(writer, value.len);
    try writer.writeAll(value);
}

pub fn encodeStringField(writer: anytype, field_number: u32, value: []const u8) !void {
    try encodeBytesField(writer, field_number, value);
}

pub fn encodeVarintField(writer: anytype, field_number: u32, value: u64) !void {
    try encodeKey(writer, field_number, .varint);
    try encodeVarint(writer, value);
}

pub const Decoder = struct {
    data: []const u8,
    pos: usize,

    pub fn init(data: []const u8) Decoder {
        return .{ .data = data, .pos = 0 };
    }

    pub fn eof(self: *Decoder) bool {
        return self.pos >= self.data.len;
    }

    pub fn readVarint(self: *Decoder) !u64 {
        var shift: u6 = 0;
        var result: u64 = 0;
        while (true) {
            if (self.pos >= self.data.len) return error.UnexpectedEof;
            const byte = self.data[self.pos];
            self.pos += 1;
            result |= (@as(u64, byte & 0x7F) << shift);
            if (byte & 0x80 == 0) break;
            shift += 7;
            if (shift >= 64) return error.VarintOverflow;
        }
        return result;
    }

    pub fn readBytes(self: *Decoder, allocator: std.mem.Allocator) ![]u8 {
        const len = try self.readVarint();
        if (self.pos + len > self.data.len) return error.UnexpectedEof;
        const slice = self.data[self.pos .. self.pos + @as(usize, @intCast(len))];
        self.pos += @as(usize, @intCast(len));
        return allocator.dupe(u8, slice);
    }

    pub fn skipField(self: *Decoder, wire_type: WireType) !void {
        switch (wire_type) {
            .varint => {
                _ = try self.readVarint();
            },
            .length_delimited => {
                const len = try self.readVarint();
                if (self.pos + len > self.data.len) return error.UnexpectedEof;
                self.pos += @as(usize, @intCast(len));
            },
        }
    }
};
