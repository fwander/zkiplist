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

        /// a Key Value pair. Will be used as Inner for BufWrap
        const KVPair = struct {
            key: K,
            val: V,
        };

        /// Allows us to reinterp the data of a freed node
        /// as a linked list
        const RmNode = struct {
            next: ?*RmNode,
            height: usize,
        };

        /// skiplist node type. Is of variable size.
        const Node = bufwrap.BufWrap(KVPair, bufwrap.Self);

        head: std.ArrayList(?*Node),
        allocator: mem.Allocator,
        rand: std.rand.Random,
        last_rmd: ?*RmNode,

        const SL = @This();

        /// pop a remoed node from the free list.
        /// If not using the free list or the free
        /// list is empty, will return null, otherwise
        /// returns pointer to most recently freed node.
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

        /// Push a node to the free list, if not using
        /// the free list, simply dealloc, otherwise
        /// reinterp data and update self.last_rmd to
        /// the pointer which was passed in
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

        /// Returns a pointer to a new node, If using the free list,
        /// will return pointer to most resently freed node,
        /// otherwize will alloc a new node.
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

        /// Initialize a SkipList, needs a allocator and a rng.
        pub fn init(allocator: mem.Allocator, rand: std.rand.Random) SL {
            return SL{
                .head = std.ArrayList(?*Node).init(allocator),
                .allocator = allocator,
                .rand = rand,
                .last_rmd = null,
            };
        }

        /// returns next node height. Uses random number generator
        /// which was passed in through init.
        fn next_height(self: *SL) usize {
            var ret: usize = 1;
            while (self.rand.boolean()) {
                ret += 1;
            }
            return ret;
        }

        /// frees memory which was alloc'ed by self.
        /// walks the lowest level of the skiplist to call
        /// deinit on every node
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

        /// walks the skiplist to find target K node.
        /// @param target key to get
        fn get_node(self: *SL, target: K) ?*Node {
            var iter = WalkIter.fst(self.*, target);

            if (self.head.items.len == 0) {
                return null;
            }

            // walk self head before walking the rest of the tree
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
                    // check if the node directly to our right is
                    // who wer're looking for because iter won't
                    // ever reach that node.
                    if (SL.eq(next, target)) {
                        return next;
                    }
                }
                iter = curr.next(target);
            }
            return null;
        }

        /// get the value from a key
        /// @param key key to get
        fn get(self: *SL, key: K) ?V {
            const o_got = self.get_node(key);
            if (o_got) |got| {
                return got.inner.val;
            }
            return null;
        }

        /// set the value for a key
        /// will overide if key is present, otherwise will insert
        /// @param key key to set
        /// @param val val to set
        fn set(self: *SL, key: K, val: V) !void {
            var o_got = self.get_node(key);
            if (o_got) |got| {
                got.inner.val = val;
                return;
            }
            return self.add(key, val);
        }

        /// add a new key value pair. If key was present will
        /// break struct invariants.
        /// @param key key to add
        /// @param val val to add
        fn add(self: *SL, key: K, val: V) !void {
            var node = try self.new_node(self.allocator, key, val, self.next_height());

            var iter = WalkIter.fst(self.*, key);

            // grow head arraylist to accommodate new node
            if (node.get_buf().len > self.head.items.len) {
                try self.head.appendNTimes(
                    null,
                    node.get_buf().len - self.head.items.len,
                );
            }

            // walk head to update head pointers
            var i = node.get_buf().len - 1;
            while (true) : (i -= 1) {
                // as soon as a node in the head list is smaller than
                // key, we know that it and all subsiquent nodes will
                // shadow new node.
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
                    // make sure that new node would fall in between
                    // curr.right and curr.
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
                return false;
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
            _ = list.remove(key);
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
