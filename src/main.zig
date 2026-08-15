const r4os = @import("r4os");

const App = struct {
    sys: r4os.r4sys.Context,
    net: r4os.Network,
    net_low: r4os.r4net.Context,

    fn init(app: *r4os.App) ?App {
        return .{
            .sys = app.system(),
            .net = app.network() orelse return null,
            .net_low = app.networkLowLevel() orelse return null,
        };
    }

    fn write(self: *const App, value: []const u8) void {
        self.sys.write(value);
    }

    fn putc(self: *const App, ch: u8) void {
        self.sys.putc(ch);
    }

    fn printU64(self: *const App, value: u64) void {
        self.sys.printU64(value);
    }

    fn printI32(self: *const App, value: i32) void {
        self.sys.printI32(value);
    }

    fn netConfigGet(self: *const App, out: *r4os.abi.NetConfigSnapshot) i32 {
        return self.net_low.netConfigGet(out);
    }

    fn netConfigResultName(self: *const App, result: i32) []const u8 {
        return self.net_low.netConfigResultName(result);
    }
};

pub fn r4_app_main(app: *r4os.App) i32 {
    const ctx = App.init(app) orelse return r4os.abi.err_no_group;
    const args = trim(app.args());
    if (args.len == 0 or equalsIgnoreCase(args, "/?") or equalsIgnoreCase(args, "-?")) {
        usage(&ctx);
        return 1;
    }

    const options = parseOptions(args) orelse {
        usage(&ctx);
        return 1;
    };

    if (options.invalid_server) {
        ctx.write("DNSLOOKUP: invalid server\r\n");
        usage(&ctx);
        return 1;
    }

    var resolver = ctx.net.resolver();
    const server = if (options.server) |value| r4os.Ipv4Address.fromBytes(value) else null;
    const result = resolver.resolveA(options.name, server, r4os.time_contract.timeoutFinite(r4os.time_contract.durationFromNanoseconds(5_000_000_000)));
    printServer(&ctx, options.server);
    ctx.write("DNS resolve ");
    ctx.write(options.name);
    ctx.write(": ");
    return switch (result) {
        .address => |address| blk: {
            ctx.write("ok ");
            writeIpv4(&ctx, address.octets);
            ctx.write("\r\n");
            ctx.write("Name . . . . . . . . . . : ");
            ctx.write(options.name);
            ctx.write("\r\n");
            ctx.write("Address  . . . . . . . . : ");
            writeIpv4(&ctx, address.octets);
            ctx.write("\r\n");
            break :blk 0;
        },
        .timed_out => blk: {
            ctx.write("timeout\r\n");
            break :blk 1;
        },
        .not_found => blk: {
            ctx.write("not found\r\n");
            break :blk 1;
        },
        .no_service => blk: {
            ctx.write("DNS service unavailable\r\n");
            break :blk 1;
        },
        .failure => |raw_code| blk: {
            ctx.write("failed code=");
            ctx.printI32(raw_code);
            ctx.write("\r\n");
            break :blk 1;
        },
    };
}

fn usage(ctx: *const App) void {
    ctx.write("Usage: DNSLOOKUP hostname [server]\r\n");
}

fn printServer(ctx: *const App, explicit_server: ?[4]u8) void {
    if (explicit_server) |server| {
        ctx.write("Server . . . . . . . . . : ");
        writeIpv4(ctx, server);
        ctx.write(" (explicit)\r\n");
        return;
    }

    var snapshot: r4os.abi.NetConfigSnapshot = .{};
    const result = ctx.netConfigGet(&snapshot);
    if (result != r4os.abi.net_config_ok) {
        ctx.write("Server . . . . . . . . . : unavailable (");
        ctx.write(ctx.netConfigResultName(result));
        ctx.write(")\r\n");
        return;
    }

    ctx.write("Server . . . . . . . . . : ");
    if ((snapshot.flags & r4os.abi.net_config_flag_dns_configured) != 0) {
        writeIpv4(ctx, snapshot.dns_ip);
    } else {
        ctx.write("not configured");
    }
    ctx.write("\r\n");
}

const Options = struct {
    name: []const u8,
    server: ?[4]u8 = null,
    invalid_server: bool = false,
};

fn parseOptions(args: []const u8) ?Options {
    const first = takeToken(args) orelse return null;
    if (first.rest.len == 0) return .{ .name = first.token };

    const second = takeToken(first.rest) orelse return null;
    if (second.rest.len != 0) return null;

    return .{
        .name = first.token,
        .server = parseIpv4(second.token) orelse return .{ .name = first.token, .invalid_server = true },
    };
}

fn writeIpv4(ctx: *const App, ip: [4]u8) void {
    ctx.printU64(ip[0]);
    ctx.putc('.');
    ctx.printU64(ip[1]);
    ctx.putc('.');
    ctx.printU64(ip[2]);
    ctx.putc('.');
    ctx.printU64(ip[3]);
}

const Token = struct {
    token: []const u8,
    rest: []const u8,
};

fn takeToken(value: []const u8) ?Token {
    const trimmed = trim(value);
    if (trimmed.len == 0) return null;
    var end: usize = 0;
    while (end < trimmed.len and !isSpace(trimmed[end])) : (end += 1) {}
    return .{
        .token = trimmed[0..end],
        .rest = if (end >= trimmed.len) "" else trim(trimmed[end..]),
    };
}

fn trim(value: []const u8) []const u8 {
    var start: usize = 0;
    var end = value.len;
    while (start < end and isSpace(value[start])) : (start += 1) {}
    while (end > start and isSpace(value[end - 1])) : (end -= 1) {}
    return value[start..end];
}

fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n';
}

fn parseIpv4(value: []const u8) ?[4]u8 {
    var ip: [4]u8 = .{0} ** 4;
    var part: usize = 0;
    var acc: u32 = 0;
    var have_digit = false;

    for (value) |ch| {
        if (ch >= '0' and ch <= '9') {
            have_digit = true;
            acc = acc * 10 + @as(u32, ch - '0');
            if (acc > 255) return null;
        } else if (ch == '.') {
            if (!have_digit or part >= 3) return null;
            ip[part] = @intCast(acc);
            part += 1;
            acc = 0;
            have_digit = false;
        } else {
            return null;
        }
    }

    if (!have_digit or part != 3) return null;
    ip[part] = @intCast(acc);
    return ip;
}

fn equalsIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var index: usize = 0;
    while (index < a.len) : (index += 1) {
        if (asciiUpper(a[index]) != asciiUpper(b[index])) return false;
    }
    return true;
}

fn asciiUpper(ch: u8) u8 {
    if (ch >= 'a' and ch <= 'z') return ch - 32;
    return ch;
}
