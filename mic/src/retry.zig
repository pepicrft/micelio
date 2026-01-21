const std = @import("std");

pub const RetryConfig = struct {
    max_attempts: u32 = 3,
    initial_delay_ms: u64 = 100,
    max_delay_ms: u64 = 5000,
    multiplier: u64 = 2,
};

pub const default_config = RetryConfig{};

/// Retries an operation with exponential backoff.
/// Returns the result of the first successful call, or the last error.
pub fn withRetry(
    comptime T: type,
    comptime ErrorSet: type,
    config: RetryConfig,
    context: anytype,
    comptime operation: fn (@TypeOf(context)) ErrorSet!T,
) ErrorSet!T {
    var attempt: u32 = 0;
    var delay_ms = config.initial_delay_ms;
    var last_error: ErrorSet = undefined;

    while (attempt < config.max_attempts) {
        if (operation(context)) |result| {
            return result;
        } else |err| {
            last_error = err;

            // Check if error is retryable
            if (!isRetryableError(err)) {
                return err;
            }

            attempt += 1;
            if (attempt >= config.max_attempts) break;

            // Sleep with exponential backoff
            std.Thread.sleep(delay_ms * std.time.ns_per_ms);
            delay_ms = @min(delay_ms * config.multiplier, config.max_delay_ms);
        }
    }

    return last_error;
}

/// Determines if an error is worth retrying.
fn isRetryableError(err: anytype) bool {
    return switch (err) {
        // Network errors
        error.ConnectionRefused,
        error.ConnectionResetByPeer,
        error.ConnectionTimedOut,
        error.NetworkUnreachable,
        error.HostUnreachable,
        error.TemporaryNameServerFailure,
        error.ServerNameResolutionFailed,
        => true,

        // File system transient errors
        error.WouldBlock,
        error.SystemResources,
        => true,

        // Everything else is not retryable
        else => false,
    };
}

/// Simple retry wrapper for void operations.
pub fn retryVoid(
    comptime ErrorSet: type,
    config: RetryConfig,
    context: anytype,
    comptime operation: fn (@TypeOf(context)) ErrorSet!void,
) ErrorSet!void {
    var attempt: u32 = 0;
    var delay_ms = config.initial_delay_ms;
    var last_error: ErrorSet = undefined;

    while (attempt < config.max_attempts) {
        if (operation(context)) {
            return;
        } else |err| {
            last_error = err;

            if (!isRetryableError(err)) {
                return err;
            }

            attempt += 1;
            if (attempt >= config.max_attempts) break;

            std.Thread.sleep(delay_ms * std.time.ns_per_ms);
            delay_ms = @min(delay_ms * config.multiplier, config.max_delay_ms);
        }
    }

    return last_error;
}

test "retry succeeds on first try" {
    var call_count: u32 = 0;
    const Ctx = struct {
        count: *u32,

        fn operation(self: @This()) error{TestError}!u32 {
            self.count.* += 1;
            return 42;
        }
    };

    const ctx = Ctx{ .count = &call_count };
    const result = try withRetry(u32, error{TestError}, default_config, ctx, Ctx.operation);

    try std.testing.expectEqual(@as(u32, 42), result);
    try std.testing.expectEqual(@as(u32, 1), call_count);
}
