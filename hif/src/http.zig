const std = @import("std");

pub const Response = struct {
    status: std.http.Status,
    body: []u8,
};

pub fn postJson(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    url: []const u8,
    payload: []const u8,
) !Response {
    var response_storage = std.Io.Writer.Allocating.init(allocator);
    defer response_storage.deinit();

    const headers = std.http.Client.Request.Headers{
        .content_type = .{ .override = "application/json" },
    };
    const extra_headers = [_]std.http.Header{
        .{ .name = "accept", .value = "application/json" },
    };

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = payload,
        .headers = headers,
        .extra_headers = &extra_headers,
        .response_writer = &response_storage.writer,
    });

    const body = try response_storage.toOwnedSlice();
    return .{ .status = result.status, .body = body };
}
