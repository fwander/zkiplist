const std = @import("std");

pub const Self = struct {};

pub fn BufWrap(comptime to_wrap: type, comptime buf_type: type) type {
    return struct {
        inner: to_wrap,
        len: usize,

        fn get_buf_type() type {
            if (buf_type == Self) {
                return ?*@This();
            } else {
                return buf_type;
            }
        }

        const align_diff = @sizeOf(@This()) % @alignOf(get_buf_type());
        const header_size = @sizeOf(@This()) + align_diff;
        const total_align = @max(@alignOf(@This()), @alignOf(get_buf_type()));

        pub fn get_buf(self: *@This()) []get_buf_type() {
            const ret: [*]get_buf_type() = @ptrFromInt(@intFromPtr(self) + @sizeOf(@This()) + align_diff);
            return ret[0..self.len];
        }

        fn size(n: usize) usize {
            return header_size + n * @sizeOf(get_buf_type());
        }

        pub fn init(allocator: std.mem.Allocator, n: usize) !*@This() {
            const raw_memory = try allocator.alignedAlloc(
                u8,
                total_align,
                size(n),
            );
            var ret: *@This() = @ptrCast(raw_memory.ptr);
            ret.len = n;
            return ret;
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            var as_many: [*]align(total_align) u8 = @ptrCast(self);
            allocator.free(as_many[0..size(self.len)]);
        }
    };
}

test "simple" {
    const Input = struct {
        fst: i64,
        snd: i64,
    };

    var wrapped = try BufWrap(Input, u8).init(std.testing.allocator, 10);
    defer wrapped.deinit(std.testing.allocator);

    wrapped.inner.fst = 3;
    wrapped.inner.snd = 4;

    std.debug.assert(wrapped.inner.fst == 3);
    std.debug.assert(wrapped.inner.snd == 4);
}

test "use buf" {
    const Input = struct {
        fst: i64,
        snd: i64,
    };

    var wrapped = try BufWrap(Input, u8).init(std.testing.allocator, 10);
    defer wrapped.deinit(std.testing.allocator);

    var buf = wrapped.get_buf();

    wrapped.inner.snd = 4;
    buf[0] = 'a';

    std.debug.assert(wrapped.inner.snd == 4);
    std.debug.assert(wrapped.get_buf()[0] == 'a');
}

test "i32 with i16" {
    const Input = struct {
        fst: i32,
        snd: i16,
    };

    var wrapped = try BufWrap(Input, u8).init(std.testing.allocator, 10);
    defer wrapped.deinit(std.testing.allocator);

    var buf = wrapped.get_buf();

    wrapped.inner.snd = 4;
    buf[0] = 'a';

    std.debug.assert(wrapped.inner.snd == 4);
    std.debug.assert(wrapped.get_buf()[0] == 'a');
}

test "multiple uses" {
    const Input = struct {
        fst: i32,
        snd: i16,
    };

    var wrapped1 = try BufWrap(Input, u8).init(std.testing.allocator, 10);
    defer wrapped1.deinit(std.testing.allocator);

    var wrapped2 = try BufWrap(Input, u8).init(std.testing.allocator, 10);
    defer wrapped2.deinit(std.testing.allocator);

    var buf1 = wrapped1.get_buf();
    var buf2 = wrapped2.get_buf();

    wrapped1.inner.snd = 4;
    buf1[0] = 'a';

    wrapped2.inner.snd = 2;
    buf2[0] = 'b';

    std.debug.assert(wrapped1.inner.snd == 4);
    std.debug.assert(wrapped1.get_buf()[0] == 'a');

    std.debug.assert(wrapped2.inner.snd == 2);
    std.debug.assert(wrapped2.get_buf()[0] == 'b');
}

test "memset" {
    const Input = struct {
        fst: i32,
        snd: i16,
    };

    var wrapped = try BufWrap(Input, u8).init(std.testing.allocator, 10);
    defer wrapped.deinit(std.testing.allocator);

    var buf: []u8 = wrapped.get_buf();

    wrapped.inner.snd = 4;

    @memset(buf, '5');

    std.debug.assert(wrapped.inner.snd == 4);

    std.debug.assert(std.mem.eql(u8, buf, "5555555555"));
}

test "i32 buffer" {
    const Input = struct {
        fst: i32,
        snd: i16,
    };

    var wrapped = try BufWrap(Input, i32).init(std.testing.allocator, 10);
    defer wrapped.deinit(std.testing.allocator);

    var buf: []i32 = wrapped.get_buf();

    wrapped.inner.snd = 4;

    buf[9] = 3;

    std.debug.assert(wrapped.inner.snd == 4);

    std.debug.assert(wrapped.get_buf()[9] == 3);
}
