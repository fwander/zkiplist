const std = @import("std");
const mem = std.mem;

const cmp = @import("cmp.zig");
const bufwrap = @import("bufwrap.zig");

const Options = struct {
    reuse_nodes: bool = true,
};

pub fn SkipList(comptime K: type, comptime V: type, comptime options: Options) type {
    return struct {
        /// True if fst is less than snd
        ///
        fn less_than(
            fst: ?*Node,
            snd: K,
        ) bool {
            if (fst) |f| {
                return cmp.lt(f.inner.key, snd);
            } else {
                return false;
            }
        }

        /// True if fst is equal to snd
        ///
        fn eq(
            fst: ?*Node,
            snd: K,
        ) bool {
            if (fst) |f| {
                return cmp.eq(f.inner.key, snd);
            } else {
                return false;
            }
        }

        /// True if fst is greater than snd
        ///
        fn greater_than(
            fst: ?*Node,
            snd: K,
        ) bool {
            if (fst) |f| {
                return cmp.gt(f.inner.key, snd);
            } else {
                return true;
            }
        }

        const KVPair = struct {
            key: K,
            val: V,
        };

        const RmNode = struct {
            next: ?*RmNode,
            height: usize,
        };

        const Node = bufwrap.BufWrap(KVPair, bufwrap.Self);

        head: std.ArrayList(?*Node),
        allocator: mem.Allocator,
        rand: std.rand.Random,
        last_rmd: ?*RmNode,

        const SL = @This();

        fn pop_rm(self: *SL) ?*Node {
            if (!options.reuse_nodes) {
                return null;
            }
            if (self.last_rmd) |rmd| {
                self.last_rmd = rmd.next;
                var ret: *Node = @ptrCast(@alignCast(rmd));
                const tmp_height = rmd.height;
                ret.len = tmp_height;
                return ret;
            }
            return null;
        }

        fn push_rm(self: *SL, node: *Node) void {
            if (!options.reuse_nodes) {
                node.deinit(self.allocator);
                return;
            }
            var as_rm: *RmNode = @ptrCast(@alignCast(node));
            const tmp_height = node.len;
            as_rm.height = tmp_height;
            as_rm.next = self.last_rmd;
            self.last_rmd = as_rm;
        }

        fn new_node(self: *SL, allocator: std.mem.Allocator, key: K, val: V, height: usize) !*Node {
            var node: *Node = undefined;
            if (self.pop_rm()) |ret| {
                node = ret;
            } else {
                node = try Node.init(allocator, height);
            }
            node.inner = .{
                .key = key,
                .val = val,
            };
            @memset(node.get_buf(), null);
            return node;
        }

        pub fn init(allocator: mem.Allocator, rand: std.rand.Random) SL {
            return SL{
                .head = std.ArrayList(?*Node).init(allocator),
                .allocator = allocator,
                .rand = rand,
                .last_rmd = null,
            };
        }

        fn next_height(self: *SL) usize {
            var ret: usize = 1;
            while (self.rand.boolean()) {
                ret += 1;
            }
            return ret;
        }

        pub fn deinit(self: *SL) void {
            if (self.head.items.len != 0) {
                var o_node = self.head.items[0];

                while (o_node) |node| {
                    defer node.deinit(self.allocator);
                    o_node = node.get_buf()[0];
                }
            }
            self.head.deinit();
        }

        fn get_node(self: *SL, target: K) ?*Node {
            var iter = WalkIter.fst(self.*, target);

            if (self.head.items.len == 0) {
                return null;
            }

            var i = self.head.items.len - 1;
            while (true) : (i -= 1) {
                const node = self.head.items[i];
                if (SL.eq(node, target)) {
                    return node;
                }
                if (SL.less_than(node, target)) {
                    break;
                }
                if (i == 0) {
                    break;
                }
            }

            while (iter) |curr| {
                if (curr.right()) |next| {
                    if (SL.eq(next, target)) {
                        return next;
                    }
                }
                iter = curr.next(target);
            }
            return null;
        }

        fn get(self: *SL, key: K) ?V {
            const o_got = self.get_node(key);
            if (o_got) |got| {
                return got.inner.val;
            }
            return null;
        }

        fn set(self: *SL, key: K, val: V) !void {
            var o_got = self.get_node(key);
            if (o_got) |got| {
                got.inner.val = val;
                return;
            }
            return self.add(key, val);
        }

        fn add(self: *SL, key: K, val: V) !void {
            var node = try self.new_node(self.allocator, key, val, self.next_height());

            var iter = WalkIter.fst(self.*, key);

            if (node.get_buf().len > self.head.items.len) {
                try self.head.appendNTimes(
                    null,
                    node.get_buf().len - self.head.items.len,
                );
            }

            var i = node.get_buf().len - 1;
            while (true) : (i -= 1) {
                if (SL.less_than(self.head.items[i], key)) {
                    break;
                }
                node.get_buf()[i] = self.head.items[i];
                self.head.items[i] = node;

                if (i == 0) {
                    break;
                }
            }

            while (iter) |curr| {
                iter = curr.next(key);
                if (curr.height <= node.get_buf().len - 1) {
                    if (SL.greater_than(curr.right(), key)) {
                        node.get_buf()[curr.height] = curr.right();
                        curr.node.get_buf()[curr.height] = node;
                    }
                }
            }
        }

        /// remove a key from the skiplist
        /// @param key key to remove
        /// @return true if key was present, false if not
        fn remove(self: *SL, key: K) bool {
            var iter = WalkIter.fst(self.*, key);

            var removing: ?*Node = null;

            if (self.head.items.len == 0) {
                return;
            }

            var i = self.head.items.len - 1;
            while (true) : (i -= 1) {
                const node = self.head.items[i];
                if (SL.eq(node, key)) {
                    self.head.items[i] = node.?.get_buf()[i];
                    removing = node;
                }
                if (SL.less_than(node, key)) {
                    break;
                }
                if (i == 0) {
                    break;
                }
            }

            while (iter) |curr| {
                iter = curr.next(key);
                if (curr.right()) |next| {
                    if (SL.eq(next, key)) {
                        curr.node.get_buf()[curr.height] = next.get_buf()[curr.height];
                        removing = next;
                    }
                }
            }

            if (removing) |rm| {
                self.push_rm(rm);
                return true;
            }
            return false;
        }

        const WalkIter = struct {
            node: *Node,
            height: usize,

            /// Will cause .node to be the first node in the skiplist which
            /// is on the path to target
            /// Will return null if there is no path to target
            pub fn fst(skip_list: SL, target: K) ?@This() {
                if (skip_list.head.items.len == 0) {
                    return null;
                }

                var starting_node: ?*Node = null;

                // find starting node by walking down from the head's outgoing edges
                // and looking for the first node which is less than or equal to target
                var i: usize = skip_list.head.items.len - 1;
                while (true) {
                    const node = skip_list.head.items[i];
                    if (less_than(node, target)) {
                        starting_node = node;
                        break;
                    }
                    if (i == 0) {
                        break;
                    }
                    i -= 1;
                }

                if (starting_node) |node| {
                    return WalkIter{
                        .node = node,
                        .height = node.get_buf().len - 1,
                    };
                }
                return null;
            }

            pub fn right(self: @This()) ?*Node {
                return self.node.get_buf()[self.height];
            }

            pub fn next(self: @This(), target: K) ?@This() {
                if (SL.eq(self.node, target)) return null;

                // if the node to the right is less than what we're looking for we can stop going down
                // and instead go to the right
                if (!SL.less_than(self.right(), target)) {
                    if (self.height == 0) {
                        return null;
                    }
                    return WalkIter{
                        .height = self.height - 1,
                        .node = self.node,
                    };
                }

                if (self.right()) |next_node| {
                    return WalkIter{
                        .height = self.height,
                        .node = next_node,
                    };
                }
                return null;
            }
        };
    };
}

pub fn main() !void {
    var myRand = std.rand.DefaultPrng.init(1234);
    var myGpa = std.heap.GeneralPurposeAllocator(.{}){};
    var list = SkipList(i32, i32, .{
        .reuse_nodes = true,
    }).init(myGpa.allocator(), myRand.random());
    var gld_list = std.hash_map.AutoHashMap(i32, i32).init(myGpa.allocator());
    _ = gld_list;
    //defer list.deinit();

    var r = myRand.random();
    var iter: i32 = 0;
    while (iter < 1000000) : (iter += 1) {
        const key = @mod(r.int(i32), 100000);
        const val = @mod(r.int(i32), 100000);
        if (r.int(i32) & 1 != 0) {
            list.remove(key);
            //_ = gld_list.remove(key);
        } else {
            try list.set(key, val);
            //try gld_list.put(key, val);
        }
    }

    //var gld_iter = gld_list.iterator();

    //while (gld_iter.next()) |curr| {
    //std.debug.print("key: {any}: seen: {any}\n", .{
    //curr.key_ptr.*,
    //list.get(curr.key_ptr.*),
    //});
    //std.debug.assert(list.get(curr.key_ptr.*) == curr.value_ptr.*);
    //}
}
