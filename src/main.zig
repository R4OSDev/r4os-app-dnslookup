const std = @import("std");
const r4os = @import("r4os");
const family = r4os.network_family;
const a = r4os.abi;

const Options = struct {
    name: []const u8 = "",
    server: a.NetworkEndpoint = .{},
    family: u32 = 4,
};

pub fn r4_app_main(app: *r4os.App2) i32 {
    const sys = app.system();
    const options = parseOptions(app.args()) orelse {
        sys.println("Usage: DNSLOOKUP [-4|-6] hostname [server]");
        sys.println("IPv6 server syntax [address%numeric-interface]:port");
        return 1;
    };
    const clock = app.clock() catch return a.err_no_fn;
    var budget = r4os.rpc_budget.Budget.fromTimeout(clock.read, .{ .kind = a.timeout_kind_finite, .nanoseconds = 5_000_000_000 }) catch |err| return r4os.rpc_budget.code(err);
    var client: family.Client = undefined;
    const opened = app.networkFamily(.dns, &client);
    if (opened != 0) {
        sys.println("DNS service unavailable");
        return 1;
    }
    var answers: [32]a.NetworkResolveAnswer = undefined;
    var count: u32 = 0;
    const rc = family.resolveAll(&client, options.name, options.family, options.server, &budget, &answers, &count);
    const closed = client.close();
    sys.write("Server . . . . . . . . . : ");
    if (options.server.address.family != 0) {
        writeAddress(sys, options.server.address);
        if (options.server.port != 53) {
            sys.write(" port=");
            sys.printU64(options.server.port);
        }
        sys.println(" (explicit)");
    } else sys.println("configured resolver order");
    sys.write("DNS resolve ");
    sys.write(options.name);
    sys.write(": ");
    if (rc != 0 or closed < 0) {
        const failure = if (rc != 0) rc else closed;
        switch (failure) {
            a.network_error_timeout, a.service_api_result_timeout => sys.println("timeout"),
            a.network_error_not_found => sys.println("not found"),
            a.network_error_unsupported_family => sys.println("requested address family unavailable"),
            else => {
                sys.write("failed code=");
                sys.printI32(failure);
                sys.write("\r\n");
            },
        }
        return 1;
    }
    sys.write("ok ");
    writeAddress(sys, answers[0].address);
    sys.write("\r\nName . . . . . . . . . . : ");
    sys.write(options.name);
    sys.write("\r\n");
    for (answers[0..count]) |answer| {
        sys.write("Address  . . . . . . . . : ");
        writeAddress(sys, answer.address);
        sys.write("\r\n");
    }
    return 0;
}

fn parseOptions(raw: []const u8) ?Options {
    var detail: r4os.arguments.Failure = .{};
    var cursor = r4os.arguments.ArgCursor.init(raw, .{ .switches = r4os.arguments.dash | r4os.arguments.slash }, &detail) catch return null;
    var result: Options = .{};
    var have_family = false;
    var have_server = false;
    while (cursor.next() catch return null) |token| {
        const value = token.bytes(raw) catch return null;
        if (token.switch_prefix != 0) {
            if (have_family) return null;
            if (std.ascii.eqlIgnoreCase(value, "-4") or std.ascii.eqlIgnoreCase(value, "/A")) {
                result.family = 4;
            } else if (std.ascii.eqlIgnoreCase(value, "-6") or std.ascii.eqlIgnoreCase(value, "/AAAA")) {
                result.family = 6;
            } else return null;
            have_family = true;
        } else if (result.name.len == 0) {
            if (value.len == 0) return null;
            result.name = value;
        } else {
            if (have_server) return null;
            result.server = family.parseEndpoint(value, 53) orelse return null;
            have_server = true;
        }
    }
    if (result.name.len == 0) return null;
    return result;
}

fn writeAddress(sys: r4os.r4sys.Context, address: a.NetworkAddress) void {
    var buffer: [80]u8 = undefined;
    sys.write(family.addressText(&buffer, address) catch "unknown");
}

test "migration dns CLI retains IPv4 and explicitly selects AAAA and numeric scope" {
    try std.testing.expectEqual(@as(u32, 4), parseOptions("ping.r4os 010.0.2.053").?.family);
    const options = parseOptions("/AAAA \"pages.r4os\" [fe80::1%17]:5353").?;
    try std.testing.expectEqual(@as(u32, 6), options.family);
    try std.testing.expectEqual(@as(u32, 17), options.server.address.interface_id);
    try std.testing.expectEqual(@as(u16, 5353), options.server.port);
    try std.testing.expect(parseOptions("-6 ping.r4os [fe80::1]") == null);
    try std.testing.expect(parseOptions("-4 -6 ping.r4os") == null);
    try std.testing.expect(parseOptions("ping.r4os server trailing") == null);
}
