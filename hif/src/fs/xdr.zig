const std = @import("std");

pub const Reader = struct {
    data: []const u8,
    offset: usize = 0,

    pub fn init(data: []const u8) Reader {
        return .{ .data = data };
    }

    pub fn readU32(self: *Reader) !u32 {
        if (self.offset + 4 > self.data.len) return error.EndOfStream;
        const value = std.mem.readInt(u32, self.data[self.offset .. self.offset + 4], .big);
        self.offset += 4;
        return value;
    }

    pub fn readU64(self: *Reader) !u64 {
        const hi = try self.readU32();
        const lo = try self.readU32();
        return (@as(u64, hi) << 32) | @as(u64, lo);
    }

    pub fn readBool(self: *Reader) !bool {
        const value = try self.readU32();
        return value != 0;
    }

    pub fn readOpaque(self: *Reader) ![]const u8 {
        const len = try self.readU32();
        if (self.offset + len > self.data.len) return error.EndOfStream;
        const out = self.data[self.offset .. self.offset + len];
        self.offset += len;

        const pad = padLen(len);
        if (self.offset + pad > self.data.len) return error.EndOfStream;
        self.offset += pad;
        return out;
    }

    pub fn readString(self: *Reader) ![]const u8 {
        return self.readOpaque();
    }
};

pub const Writer = struct {
    list: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Writer {
        return .{ .list = std.ArrayList(u8).init(allocator, null) };
    }

    pub fn deinit(self: *Writer) void {
        self.list.deinit();
        self.* = undefined;
    }

    pub fn writeU32(self: *Writer, value: u32) !void {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, value, .big);
        try self.list.appendSlice(&buf);
    }

    pub fn writeU64(self: *Writer, value: u64) !void {
        try self.writeU32(@intCast(value >> 32));
        try self.writeU32(@intCast(value & 0xffffffff));
    }

    pub fn writeBool(self: *Writer, value: bool) !void {
        try self.writeU32(if (value) 1 else 0);
    }

    pub fn writeOpaque(self: *Writer, bytes: []const u8) !void {
        try self.writeU32(@intCast(bytes.len));
        try self.list.appendSlice(bytes);
        const pad = padLen(bytes.len);
        if (pad > 0) {
            var zeros: [3]u8 = .{ 0, 0, 0 };
            try self.list.appendSlice(zeros[0..pad]);
        }
    }

    pub fn writeString(self: *Writer, value: []const u8) !void {
        try self.writeOpaque(value);
    }

    pub fn toOwnedSlice(self: *Writer, allocator: std.mem.Allocator) ![]u8 {
        return self.list.toOwnedSlice(allocator);
    }
};

fn padLen(len: usize) usize {
    const rem = len % 4;
    return if (rem == 0) 0 else 4 - rem;
}
