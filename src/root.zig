// RobinHood HashMap

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Generic context for hashmap
pub fn AutoContext(comptime K: type) type {
    return struct {
        pub fn hash(_: @This(), key: K) usize {
            return std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
        }

        pub fn eql(_: @This(), a: K, b: K) bool {
            return std.meta.eql(a, b);
        }
    };
}

/// String context for hashmap
pub fn StringContext() type {
    return struct {
        pub fn hash(_: @This(), key: []const u8) usize {
            return std.hash.Wyhash.hash(0, key);
        }

        pub fn eql(_: @This(), a: []const u8, b: []const u8) bool {
            return std.mem.eql(u8, a, b);
        }
    };
}

/// Robinhood Hashmap
pub fn RobinHoodHashMap(comptime K: type, comptime V: type, comptime Context: type, comptime max_load_percentage: u8) type {
    return struct {
        const Self = @This();

        /// HashMap Entry (used for iterator)
        const Entry = struct {
            key_ptr: *K,
            value_ptr: *V,
        };

        /// Internal HashMap Entry
        const BucketEntry = struct {
            key: K,
            value: V,
            psl: u32, // probe sequence length
            occupied: bool,
        };

        /// Iterator
        pub const Iterator = struct {
            table: *const Self,
            index: usize,

            pub fn next(self: *Iterator) ?Entry {
                while (self.index < self.table._buckets.len) {
                    if (self.table._buckets[self.index].occupied) {
                        const entry = Entry{
                            .key_ptr = &self.table._buckets[self.index].key,
                            .value_ptr = &self.table._buckets[self.index].value,
                        };
                        self.index += 1;
                        return entry;
                    } else {
                        self.index += 1;
                    }
                }
                return null;
            }
        };

        /// Key iterator
        pub const KeyIterator = struct {
            table: *const Self,
            index: usize,

            pub fn next(self: *KeyIterator) ?K {
                while (self.index < self.table._buckets.len) {
                    if (self.table._buckets[self.index].occupied) {
                        const val = self.table._buckets[self.index].key;
                        self.index += 1;
                        return val;
                    } else {
                        self.index += 1;
                    }
                }
                return null;
            }
        };

        /// Value iterator
        pub const ValueIterator = struct {
            table: *const Self,
            index: usize,

            pub fn next(self: *ValueIterator) ?*const V {
                while (self.index < self.table._buckets.len) {
                    if (self.table._buckets[self.index].occupied) {
                        const val = &self.table._buckets[self.index].value;
                        self.index += 1;
                        return val;
                        // return @constCast(val);
                    } else {
                        self.index += 1;
                    }
                }
                return null;
            }
        };

        /// Return value of a GetOrPut call
        pub const GetOrPutResult = struct {
            key_ptr: *K,
            value_ptr: *V,
            found_existing: bool,
        };

        _buckets: []BucketEntry,
        _bucket_count: usize,
        _allocator: Allocator,
        _ctx: Context,
        _max_load_percentage: u8,

        const default_capacity: u8 = 16;

        /// Initialize hashmap
        pub fn init(allocator: Allocator, ctx: Context) !Self {
            if (max_load_percentage <= 0 or max_load_percentage >= 100) {
                return error.InvalidMaxLoadPercentage;
            }

            // For performance, capacity should be power of 2
            // There is code that works on this assumption, do not remove blindly
            const new_capacity = try std.math.ceilPowerOfTwo(usize, default_capacity);
            const entries = try allocator.alloc(BucketEntry, new_capacity);
            @memset(entries, .{
                .key = undefined,
                .value = undefined,
                .psl = 0,
                .occupied = false,
            });

            return Self{
                ._buckets = entries,
                ._bucket_count = 0,
                ._allocator = allocator,
                ._ctx = ctx,
                ._max_load_percentage = max_load_percentage,
            };
        }

        /// Deinitialize the hashmap
        pub fn deinit(self: *Self) void {
            self._allocator.free(self._buckets);
        }

        /// Put value into hashmap
        pub fn put(self: *Self, key: K, value: V) !void {
            if (self._bucket_count * 100 >= self._buckets.len * self._max_load_percentage) {
                try self.resize(self._allocator);
            }

            var idx = self._ctx.hash(key) % self._buckets.len;
            var psl: u32 = 0;
            var curr_key = key;
            var curr_value = value;

            while (true) {
                const entry = &self._buckets[idx];

                if (!entry.occupied) {
                    entry.* = .{
                        .key = curr_key,
                        .value = curr_value,
                        .psl = psl,
                        .occupied = true,
                    };
                    self._bucket_count += 1;
                    return;
                }

                if (self._ctx.eql(entry.key, curr_key)) {
                    entry.value = curr_value;
                    return;
                }

                if (psl > entry.psl) {
                    std.mem.swap(K, &entry.key, &curr_key);
                    std.mem.swap(V, &entry.value, &curr_value);
                    std.mem.swap(u32, &entry.psl, &psl);
                }

                idx = (idx + 1) % self._buckets.len;
                psl += 1;

                if (psl > self._buckets.len) unreachable;
            }
        }

        /// Get value of hashmap
        pub fn get(self: *const Self, key: K) ?V {
            var idx = self._ctx.hash(key) % self._buckets.len;
            var psl: u32 = 0;

            while (true) {
                const entry = &self._buckets[idx];

                if (!entry.occupied) {
                    return null;
                }

                if (self._ctx.eql(entry.key, key)) {
                    return entry.value;
                }

                if (psl > entry.psl) {
                    return null;
                }

                idx = (idx + 1) % self._buckets.len;
                psl += 1;
            }
        }

        /// Get ptr to value of key
        pub fn getPtr(self: *Self, key: K) ?*V {
            var idx = self._ctx.hash(key) % self._buckets.len;
            var psl: u32 = 0;

            while (true) {
                const entry = &self._buckets[idx];

                if (!entry.occupied) {
                    return null;
                }

                if (self._ctx.eql(entry.key, key)) {
                    return &entry.value;
                }

                if (psl > entry.psl) {
                    return null;
                }

                idx = (idx + 1) % self._buckets.len;
                psl += 1;
            }
        }

        /// Get key and value ptrs
        pub fn getOrPut(self: *Self, key: K) !GetOrPutResult {
            if (self._bucket_count * 100 >= self._buckets.len * self._max_load_percentage) {
                try self.resize(self._allocator);
            }

            var idx = self._ctx.hash(key) % self._buckets.len;
            var psl: u32 = 0;
            var current_key = key;
            var current_value: V = undefined;
            var inserting = true;
            var result: GetOrPutResult = undefined;

            while (true) {
                const entry = &self._buckets[idx];

                if (!entry.occupied) {
                    // insert
                    entry.* = .{
                        .key = current_key,
                        .value = current_value,
                        .psl = psl,
                        .occupied = true,
                    };

                    if (inserting) {
                        self._bucket_count += 1;
                        return GetOrPutResult{
                            .key_ptr = &entry.key,
                            .value_ptr = &entry.value,
                            .found_existing = false,
                        };
                    }

                    idx = (idx + 1) % self._buckets.len;
                    psl += 1;
                    break;
                }

                if (inserting and self._ctx.eql(entry.key, current_key)) {
                    // found it, return
                    return GetOrPutResult{
                        .key_ptr = &entry.key,
                        .value_ptr = &entry.value,
                        .found_existing = true,
                    };
                }

                // Swap if current PSL > entry PSL
                if (psl > entry.psl) {
                    const temp_key = entry.key;
                    const temp_value = entry.value;
                    const temp_psl = entry.psl;

                    entry.key = current_key;
                    entry.value = current_value;
                    entry.psl = psl;

                    if (inserting) {
                        self._bucket_count += 1;
                        result = GetOrPutResult{
                            .key_ptr = &entry.key,
                            .value_ptr = &entry.value,
                            .found_existing = false,
                        };
                        current_key = temp_key;
                        current_value = temp_value;
                        psl = temp_psl;
                        inserting = false;
                        idx = (idx + 1) % self._buckets.len;
                        psl += 1;
                        continue;
                    } else {
                        current_key = temp_key;
                        current_value = temp_value;
                        psl = temp_psl;
                    }
                }

                idx = (idx + 1) % self._buckets.len;
                psl += 1;

                if (psl > self._buckets.len) unreachable;
            }

            return result;
        }

        /// Clear all capacity
        pub fn clearRetainingCapacity(self: *Self) void {
            @memset(self._buckets, .{
                .key = undefined,
                .value = undefined,
                .psl = 0,
                .occupied = false,
            });
            self._bucket_count = 0;
        }

        /// Clear capacity and free underlying storage
        pub fn clearAndFree(self: *Self) !void {
            self._allocator.free(self._buckets);

            const new_capacity = try std.math.ceilPowerOfTwo(usize, default_capacity);
            const entries = try self._allocator.alloc(BucketEntry, new_capacity);
            @memset(entries, .{
                .key = undefined,
                .value = undefined,
                .psl = 0,
                .occupied = false,
            });

            self._bucket_count = 0;
        }

        /// Clone hashmap
        pub fn clone(self: *const Self) !Self {
            const new_buckets = try self._allocator.alloc(BucketEntry, self._buckets.len);
            @memcpy(new_buckets, self._buckets);

            return Self{
                ._buckets = new_buckets,
                ._bucket_count = self._bucket_count,
                ._allocator = self._allocator,
                ._ctx = self._ctx,
                ._max_load_percentage = self._max_load_percentage,
            };
        }

        /// Contains key
        pub fn contains(self: *const Self, key: K) bool {
            var idx = self._ctx.hash(key) % self._buckets.len;
            var psl: u32 = 0;

            while (true) {
                const entry = &self._buckets[idx];

                if (!entry.occupied) {
                    return false;
                }

                if (self._ctx.eql(entry.key, key)) {
                    return true;
                }

                if (psl > entry.psl) {
                    return false;
                }

                idx = (idx + 1) % self._buckets.len;
                psl += 1;
            }
        }

        /// Remove key
        /// Returns: true if found, else false
        pub fn remove(self: *Self, key: K) bool {
            var idx = self._ctx.hash(key) % self._buckets.len;
            var psl: u32 = 0;

            while (self._buckets[idx].occupied) {
                if (self._ctx.eql(self._buckets[idx].key, key)) {
                    self._buckets[idx].occupied = false;
                    self._bucket_count -= 1;

                    var next_idx = (idx + 1) % self._buckets.len;
                    while (self._buckets[next_idx].occupied and self._buckets[next_idx].psl > 0) {
                        self._buckets[idx] = self._buckets[next_idx];
                        self._buckets[idx].psl -= 1;
                        self._buckets[next_idx].occupied = false;
                        idx = next_idx;
                        next_idx = (idx + 1) % self._buckets.len;
                    }

                    return true;
                }

                if (psl > self._buckets[idx].psl) {
                    return false;
                }

                idx = (idx + 1) % self._buckets.len;
                psl += 1;
            }

            return false;
        }

        /// Resize capacity
        fn resize(self: *Self, allocator: Allocator) error{OutOfMemory}!void {
            const new_capacity = self._buckets.len * 2;
            const old_entries = self._buckets;
            const old_count = self._bucket_count;

            // New underlying array
            self._buckets = try allocator.alloc(BucketEntry, new_capacity);

            @memset(self._buckets, .{
                .key = undefined,
                .value = undefined,
                .psl = 0,
                .occupied = false,
            });
            self._bucket_count = 0;

            // Copy to new array
            for (old_entries) |entry| {
                if (entry.occupied) {
                    try self.put(entry.key, entry.value);
                }
            }

            // Verify no elements were lost
            std.debug.assert(self._bucket_count == old_count);

            // Cleanup
            self._allocator.free(old_entries);
        }

        /// Count of elements in hash
        pub fn count(self: Self) usize {
            return self._bucket_count;
        }

        /// Total capacity
        pub fn capacity(self: Self) usize {
            return self._buckets.len;
        }

        /// Ensure total capacity
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) !void {
            if (self._buckets.len >= new_capacity) return;

            const actual_capacity = try std.math.ceilPowerOfTwo(usize, new_capacity);
            const old_entries = self._buckets;
            const old_count = self._bucket_count;

            self._buckets = try self._allocator.alloc(BucketEntry, actual_capacity);
            @memset(self._buckets, .{
                .key = undefined,
                .value = undefined,
                .psl = 0,
                .occupied = false,
            });
            self._bucket_count = 0;

            for (old_entries) |entry| {
                if (entry.occupied) {
                    try self.put(entry.key, entry.value);
                }
            }

            std.debug.assert(self._bucket_count == old_count);
            self._allocator.free(old_entries);
        }

        /// Ensure unused capacity
        pub fn ensureUnusedCapacity(self: *Self, additional_count: usize) !void {
            const needed_capacity = self._bucket_count + additional_count;
            const target_capacity = (needed_capacity * 100) / self._max_load_percentage + 1;
            try self.ensureTotalCapacity(target_capacity);
        }

        /// Key iterator
        pub fn iterator(self: *const Self) Iterator {
            return Iterator{
                .table = self,
                .index = 0,
            };
        }

        /// Key iterator
        pub fn keyIterator(self: *const Self) KeyIterator {
            return KeyIterator{
                .table = self,
                .index = 0,
            };
        }

        /// Value iterator
        pub fn valueIterator(self: *const Self) ValueIterator {
            return ValueIterator{
                .table = self,
                .index = 0,
            };
        }
    };
}

////////
// Tests

test "RobinHoodHashMap - init and deinit" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try std.testing.expectEqual(@as(usize, 0), map.count());
    try std.testing.expectEqual(@as(usize, 16), map.capacity());
}

test "RobinHoodHashMap - invalid max load percentage" {
    const gpa = std.testing.allocator;
    const result = RobinHoodHashMap(i32, i32, AutoContext(i32), 0).init(gpa, AutoContext(i32){});
    try std.testing.expectError(error.InvalidMaxLoadPercentage, result);

    const result2 = RobinHoodHashMap(i32, i32, AutoContext(i32), 100).init(gpa, AutoContext(i32){});
    try std.testing.expectError(error.InvalidMaxLoadPercentage, result2);
}

test "RobinHoodHashMap - put and get" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);
    try map.put(3, 300);

    try std.testing.expectEqual(@as(?i32, 100), map.get(1));
    try std.testing.expectEqual(@as(?i32, 200), map.get(2));
    try std.testing.expectEqual(@as(?i32, 300), map.get(3));
    try std.testing.expectEqual(@as(?i32, null), map.get(4));
    try std.testing.expectEqual(@as(usize, 3), map.count());
}

test "RobinHoodHashMap - put overwrites existing key" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try std.testing.expectEqual(@as(?i32, 100), map.get(1));
    try std.testing.expectEqual(@as(usize, 1), map.count());

    try map.put(1, 999);
    try std.testing.expectEqual(@as(?i32, 999), map.get(1));
    try std.testing.expectEqual(@as(usize, 1), map.count());
}

test "RobinHoodHashMap - getPtr" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);

    const ptr = map.getPtr(1);
    try std.testing.expect(ptr != null);
    try std.testing.expectEqual(@as(i32, 100), ptr.?.*);

    ptr.?.* = 999;
    try std.testing.expectEqual(@as(?i32, 999), map.get(1));

    const null_ptr = map.getPtr(999);
    try std.testing.expect(null_ptr == null);
}

test "RobinHoodHashMap - getOrPut new key" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    const result = try map.getOrPut(1);
    try std.testing.expectEqual(false, result.found_existing);
    result.value_ptr.* = 100;

    try std.testing.expectEqual(@as(?i32, 100), map.get(1));
    try std.testing.expectEqual(@as(usize, 1), map.count());
}

test "RobinHoodHashMap - getOrPut existing key" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);

    const result = try map.getOrPut(1);
    try std.testing.expectEqual(true, result.found_existing);
    try std.testing.expectEqual(@as(i32, 100), result.value_ptr.*);
    try std.testing.expectEqual(@as(usize, 1), map.count());
}

test "RobinHoodHashMap - contains" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);

    try std.testing.expect(map.contains(1));
    try std.testing.expect(map.contains(2));
    try std.testing.expect(!map.contains(3));
}

test "RobinHoodHashMap - remove" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);
    try map.put(3, 300);

    try std.testing.expect(map.remove(2));
    try std.testing.expectEqual(@as(?i32, null), map.get(2));
    try std.testing.expectEqual(@as(usize, 2), map.count());
    try std.testing.expect(!map.contains(2));

    try std.testing.expect(!map.remove(999));
    try std.testing.expectEqual(@as(usize, 2), map.count());
}

test "RobinHoodHashMap - multiple inserts and removes" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    var i: i32 = 0;
    while (i < 50) : (i += 1) {
        try map.put(i, i * 10);
    }
    try std.testing.expectEqual(@as(usize, 50), map.count());

    i = 0;
    while (i < 25) : (i += 1) {
        try std.testing.expect(map.remove(i));
    }
    try std.testing.expectEqual(@as(usize, 25), map.count());

    i = 50;
    while (i < 75) : (i += 1) {
        try map.put(i, i * 10);
    }
    try std.testing.expectEqual(@as(usize, 50), map.count());

    i = 30;
    while (i < 60) : (i += 1) {
        _ = map.remove(i);
    }
    try std.testing.expectEqual(@as(usize, 20), map.count());

    i = 0;
    while (i < 25) : (i += 1) {
        try std.testing.expect(!map.contains(i));
    }

    i = 25;
    while (i < 30) : (i += 1) {
        try std.testing.expect(map.contains(i));
        try std.testing.expectEqual(@as(?i32, i * 10), map.get(i));
    }

    i = 30;
    while (i < 60) : (i += 1) {
        try std.testing.expect(!map.contains(i));
    }

    i = 60;
    while (i < 75) : (i += 1) {
        try std.testing.expect(map.contains(i));
        try std.testing.expectEqual(@as(?i32, i * 10), map.get(i));
    }
}

test "RobinHoodHashMap - clearRetainingCapacity" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);
    const old_capacity = map.capacity();

    map.clearRetainingCapacity();
    try std.testing.expectEqual(@as(usize, 0), map.count());
    try std.testing.expectEqual(old_capacity, map.capacity());
    try std.testing.expect(!map.contains(1));
}

test "RobinHoodHashMap - clearAndFree" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);

    try map.clearAndFree();
    try std.testing.expectEqual(@as(usize, 0), map.count());
    try std.testing.expectEqual(@as(usize, 16), map.capacity());
}

test "RobinHoodHashMap - clone" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);

    var cloned = try map.clone();
    defer cloned.deinit();

    try std.testing.expectEqual(map.count(), cloned.count());
    try std.testing.expectEqual(@as(?i32, 100), cloned.get(1));
    try std.testing.expectEqual(@as(?i32, 200), cloned.get(2));

    try cloned.put(3, 300);
    try std.testing.expect(!map.contains(3));
    try std.testing.expect(cloned.contains(3));
}

test "RobinHoodHashMap - resize triggers" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    const initial_capacity = map.capacity();

    var i: i32 = 0;
    while (i < 20) : (i += 1) {
        try map.put(i, i * 10);
    }

    try std.testing.expect(map.capacity() > initial_capacity);
    try std.testing.expectEqual(@as(usize, 20), map.count());

    i = 0;
    while (i < 20) : (i += 1) {
        try std.testing.expectEqual(@as(?i32, i * 10), map.get(i));
    }
}

test "RobinHoodHashMap - ensureTotalCapacity" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.ensureTotalCapacity(64);

    try std.testing.expect(map.capacity() >= 64);
    try std.testing.expectEqual(@as(?i32, 100), map.get(1));
}

test "RobinHoodHashMap - ensureUnusedCapacity" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.ensureUnusedCapacity(50);

    const usable = (map.capacity() * 75) / 100;
    try std.testing.expect(usable >= map.count() + 50);
}

test "RobinHoodHashMap - iterator" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);
    try map.put(3, 300);

    var count: usize = 0;
    var it = map.iterator();
    while (it.next()) |entry| {
        count += 1;
        try std.testing.expect(entry.key_ptr.* >= 1 and entry.key_ptr.* <= 3);
        try std.testing.expect(entry.value_ptr.* >= 100 and entry.value_ptr.* <= 300);
    }

    try std.testing.expectEqual(@as(usize, 3), count);
}

test "RobinHoodHashMap - keyIterator" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);
    try map.put(3, 300);

    var key_count: usize = 0;
    var it = map.keyIterator();
    while (it.next()) |_| {
        key_count += 1;
    }

    try std.testing.expectEqual(@as(usize, 3), key_count); //.items.len);
}

test "RobinHoodHashMap - valueIterator" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);
    try map.put(3, 300);

    var value_count: usize = 0;
    var it = map.valueIterator();
    while (it.next()) |value| {
        value_count += 1;
        try std.testing.expect(value.* >= 100 and value.* <= 300);
    }

    try std.testing.expectEqual(@as(usize, 3), value_count);
}

test "RobinHoodHashMap - StringContext" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap([]const u8, i32, StringContext(), 75).init(gpa, StringContext(){});
    defer map.deinit();

    try map.put("hello", 1);
    try map.put("world", 2);
    try map.put("zig", 3);

    try std.testing.expectEqual(@as(?i32, 1), map.get("hello"));
    try std.testing.expectEqual(@as(?i32, 2), map.get("world"));
    try std.testing.expectEqual(@as(?i32, 3), map.get("zig"));
    try std.testing.expectEqual(@as(?i32, null), map.get("missing"));
}

test "RobinHoodHashMap - collision handling" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    var i: i32 = 0;
    while (i < 100) : (i += 1) {
        try map.put(i, i * 2);
    }

    i = 0;
    while (i < 100) : (i += 1) {
        try std.testing.expectEqual(@as(?i32, i * 2), map.get(i));
    }

    try std.testing.expectEqual(@as(usize, 100), map.count());
}

test "RobinHoodHashMap - remove with collisions" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    var i: i32 = 0;
    while (i < 50) : (i += 1) {
        try map.put(i, i * 10);
    }

    i = 0;
    while (i < 25) : (i += 1) {
        try std.testing.expect(map.remove(i));
    }

    try std.testing.expectEqual(@as(usize, 25), map.count());

    i = 0;
    while (i < 25) : (i += 1) {
        try std.testing.expect(!map.contains(i));
    }

    i = 25;
    while (i < 50) : (i += 1) {
        try std.testing.expect(map.contains(i));
        try std.testing.expectEqual(@as(?i32, i * 10), map.get(i));
    }
}

test "RobinHoodHashMap - remove non-existent after existing" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);

    try std.testing.expect(!map.remove(999));
    try std.testing.expectEqual(@as(usize, 2), map.count());
}

test "RobinHoodHashMap - multiple resize cycles" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    const initial_capacity = map.capacity();

    var i: i32 = 0;
    while (i < 1000) : (i += 1) {
        try map.put(i, i * 5);
    }

    try std.testing.expect(map.capacity() > initial_capacity);
    try std.testing.expectEqual(@as(usize, 1000), map.count());

    i = 0;
    while (i < 1000) : (i += 1) {
        try std.testing.expectEqual(@as(?i32, i * 5), map.get(i));
    }
}

test "RobinHoodHashMap - ensureTotalCapacity smaller than current" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    const initial_capacity = map.capacity();
    try map.ensureTotalCapacity(8);

    try std.testing.expectEqual(initial_capacity, map.capacity());
}

test "RobinHoodHashMap - iterator modification through value_ptr" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);
    try map.put(3, 300);

    var it = map.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.* += 1000;
    }

    try std.testing.expectEqual(@as(?i32, 1100), map.get(1));
    try std.testing.expectEqual(@as(?i32, 1200), map.get(2));
    try std.testing.expectEqual(@as(?i32, 1300), map.get(3));
}

test "RobinHoodHashMap - different load factors" {
    const gpa = std.testing.allocator;

    var map_low = try RobinHoodHashMap(i32, i32, AutoContext(i32), 50).init(gpa, AutoContext(i32){});
    defer map_low.deinit();

    var map_high = try RobinHoodHashMap(i32, i32, AutoContext(i32), 90).init(gpa, AutoContext(i32){});
    defer map_high.deinit();

    var i: i32 = 0;
    while (i < 20) : (i += 1) {
        try map_low.put(i, i);
        try map_high.put(i, i);
    }

    try std.testing.expect(map_low.capacity() > map_high.capacity());
    try std.testing.expectEqual(@as(usize, 20), map_low.count());
    try std.testing.expectEqual(@as(usize, 20), map_high.count());
}

test "RobinHoodHashMap - clearRetainingCapacity and reuse" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);
    map.clearRetainingCapacity();

    try map.put(3, 300);
    try map.put(4, 400);

    try std.testing.expectEqual(@as(usize, 2), map.count());
    try std.testing.expect(!map.contains(1));
    try std.testing.expect(!map.contains(2));
    try std.testing.expectEqual(@as(?i32, 300), map.get(3));
    try std.testing.expectEqual(@as(?i32, 400), map.get(4));
}

test "RobinHoodHashMap - clearAndFree and reuse" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.clearAndFree();

    try std.testing.expectEqual(@as(usize, 16), map.capacity());

    try map.put(2, 200);
    try std.testing.expectEqual(@as(?i32, 200), map.get(2));
}

test "RobinHoodHashMap - getOrPut trigger resize" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    var i: i32 = 0;
    while (i < 20) : (i += 1) {
        const result = try map.getOrPut(i);
        result.value_ptr.* = i * 100;
    }

    try std.testing.expectEqual(@as(usize, 20), map.count());

    i = 0;
    while (i < 20) : (i += 1) {
        try std.testing.expectEqual(@as(?i32, i * 100), map.get(i));
    }
}

test "RobinHoodHashMap - clone independence" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);

    var cloned = try map.clone();
    defer cloned.deinit();

    try map.put(1, 999);
    try cloned.put(1, 888);

    try std.testing.expectEqual(@as(?i32, 999), map.get(1));
    try std.testing.expectEqual(@as(?i32, 888), cloned.get(1));
}

test "RobinHoodHashMap - ensureUnusedCapacity actual usage" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.ensureUnusedCapacity(100);

    var i: i32 = 0;
    while (i < 100) : (i += 1) {
        try map.put(i, i);
    }

    try std.testing.expectEqual(@as(usize, 100), map.count());
}

test "RobinHoodHashMap - AutoContext hash consistency" {
    const ctx = AutoContext(i32){};
    const hash1 = ctx.hash(42);
    const hash2 = ctx.hash(42);
    const hash3 = ctx.hash(43);

    try std.testing.expectEqual(hash1, hash2);
    try std.testing.expect(hash1 != hash3);
}

test "RobinHoodHashMap - AutoContext eql" {
    const ctx = AutoContext(i32){};

    try std.testing.expect(ctx.eql(42, 42));
    try std.testing.expect(!ctx.eql(42, 43));
}

test "RobinHoodHashMap - StringContext hash consistency" {
    const ctx = StringContext(){};
    const hash1 = ctx.hash("hello");
    const hash2 = ctx.hash("hello");
    const hash3 = ctx.hash("world");

    try std.testing.expectEqual(hash1, hash2);
    try std.testing.expect(hash1 != hash3);
}

test "RobinHoodHashMap - StringContext eql" {
    const ctx = StringContext(){};

    try std.testing.expect(ctx.eql("hello", "hello"));
    try std.testing.expect(!ctx.eql("hello", "world"));
    try std.testing.expect(!ctx.eql("hello", "hello!"));
}

test "RobinHoodHashMap - BucketEntry psl tracking" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    var i: i32 = 0;
    while (i < 50) : (i += 1) {
        try map.put(i, i * 2);
    }

    var has_nonzero_psl = false;
    for (map._buckets) |bucket| {
        if (bucket.occupied and bucket.psl > 0) {
            has_nonzero_psl = true;
            break;
        }
    }

    try std.testing.expect(has_nonzero_psl);
}

test "RobinHoodHashMap - Iterator empty map" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    var it = map.iterator();
    try std.testing.expect(it.next() == null);
    try std.testing.expect(it.next() == null);
}

test "RobinHoodHashMap - Iterator single element" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(42, 84);

    var it = map.iterator();
    const entry = it.next().?;
    try std.testing.expectEqual(@as(i32, 42), entry.key_ptr.*);
    try std.testing.expectEqual(@as(i32, 84), entry.value_ptr.*);
    try std.testing.expect(it.next() == null);
}

test "RobinHoodHashMap - KeyIterator empty map" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    var it = map.keyIterator();
    try std.testing.expect(it.next() == null);
}

test "RobinHoodHashMap - KeyIterator all keys" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 10);
    try map.put(2, 20);
    try map.put(3, 30);

    var key_count: usize = 0;
    var it = map.keyIterator();
    while (it.next()) |_| {
        key_count += 1;
    }

    try std.testing.expectEqual(@as(usize, 3), key_count);
}

test "RobinHoodHashMap - ValueIterator empty map" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    var it = map.valueIterator();
    try std.testing.expect(it.next() == null);
}

test "RobinHoodHashMap - ValueIterator all values" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);
    try map.put(3, 300);

    var sum: i32 = 0;
    var it = map.valueIterator();
    while (it.next()) |value| {
        sum += value.*;
    }

    try std.testing.expectEqual(@as(i32, 600), sum);
}

test "RobinHoodHashMap - ValueIterator single element" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(5, 555);

    var it = map.valueIterator();
    const value = it.next().?;
    try std.testing.expectEqual(@as(i32, 555), value.*);
    try std.testing.expect(it.next() == null);
}

test "RobinHoodHashMap - GetOrPutResult structure" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    const result = try map.getOrPut(99);
    result.key_ptr.* = 99;
    result.value_ptr.* = 999;

    try std.testing.expectEqual(false, result.found_existing);
    try std.testing.expectEqual(@as(?i32, 999), map.get(99));
}

test "RobinHoodHashMap - capacity returns correct value" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    const initial_cap = map.capacity();
    try std.testing.expectEqual(@as(usize, 16), initial_cap);

    try map.ensureTotalCapacity(64);
    try std.testing.expect(map.capacity() >= 64);
}

test "RobinHoodHashMap - count empty map" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try std.testing.expectEqual(@as(usize, 0), map.count());
}

test "RobinHoodHashMap - count after operations" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try std.testing.expectEqual(@as(usize, 0), map.count());

    try map.put(1, 10);
    try std.testing.expectEqual(@as(usize, 1), map.count());

    try map.put(2, 20);
    try std.testing.expectEqual(@as(usize, 2), map.count());

    try map.put(1, 15);
    try std.testing.expectEqual(@as(usize, 2), map.count());

    _ = map.remove(1);
    try std.testing.expectEqual(@as(usize, 1), map.count());
}

test "RobinHoodHashMap - remove empty bucket" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try std.testing.expect(!map.remove(999));
    try std.testing.expectEqual(@as(usize, 0), map.count());
}

test "RobinHoodHashMap - remove and re-add" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(1, 100);
    try std.testing.expect(map.remove(1));
    try map.put(1, 200);

    try std.testing.expectEqual(@as(?i32, 200), map.get(1));
    try std.testing.expectEqual(@as(usize, 1), map.count());
}

test "RobinHoodHashMap - remove maintains chain" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    var i: i32 = 0;
    while (i < 10) : (i += 1) {
        try map.put(i, i * 10);
    }

    _ = map.remove(5);

    i = 0;
    while (i < 10) : (i += 1) {
        if (i == 5) {
            try std.testing.expect(!map.contains(i));
        } else {
            try std.testing.expect(map.contains(i));
        }
    }
}

test "RobinHoodHashMap - resize preserves data" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        try map.put(i, i * 100);
    }

    const old_cap = map.capacity();

    while (i < 20) : (i += 1) {
        try map.put(i, i * 100);
    }

    try std.testing.expect(map.capacity() > old_cap);

    i = 0;
    while (i < 20) : (i += 1) {
        try std.testing.expectEqual(@as(?i32, i * 100), map.get(i));
    }
}

test "RobinHoodHashMap - ensureTotalCapacity power of 2" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.ensureTotalCapacity(50);

    const cap = map.capacity();
    try std.testing.expect(cap >= 50);
    try std.testing.expect(std.math.isPowerOfTwo(cap));
}

test "RobinHoodHashMap - contains after remove" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap(i32, i32, AutoContext(i32), 75).init(gpa, AutoContext(i32){});
    defer map.deinit();

    try map.put(7, 70);
    try std.testing.expect(map.contains(7));

    _ = map.remove(7);
    try std.testing.expect(!map.contains(7));
}

test "RobinHoodHashMap - string key get" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap([]const u8, i32, StringContext(), 75).init(gpa, StringContext(){});
    defer map.deinit();

    try map.put("first", 1);
    try map.put("second", 2);
    try map.put("third", 3);

    try std.testing.expectEqual(@as(?i32, 1), map.get("first"));
    try std.testing.expectEqual(@as(?i32, 2), map.get("second"));
    try std.testing.expectEqual(@as(?i32, 3), map.get("third"));
    try std.testing.expectEqual(@as(?i32, null), map.get("nonexistent"));
}

test "RobinHoodHashMap - string key put and overwrite" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap([]const u8, i32, StringContext(), 75).init(gpa, StringContext(){});
    defer map.deinit();

    try map.put("key", 100);
    try std.testing.expectEqual(@as(?i32, 100), map.get("key"));
    try std.testing.expectEqual(@as(usize, 1), map.count());

    try map.put("key", 200);
    try std.testing.expectEqual(@as(?i32, 200), map.get("key"));
    try std.testing.expectEqual(@as(usize, 1), map.count());
}

test "RobinHoodHashMap - string key remove" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap([]const u8, i32, StringContext(), 75).init(gpa, StringContext(){});
    defer map.deinit();

    try map.put("alpha", 1);
    try map.put("beta", 2);
    try map.put("gamma", 3);

    try std.testing.expect(map.remove("beta"));
    try std.testing.expectEqual(@as(?i32, null), map.get("beta"));
    try std.testing.expectEqual(@as(usize, 2), map.count());

    try std.testing.expectEqual(@as(?i32, 1), map.get("alpha"));
    try std.testing.expectEqual(@as(?i32, 3), map.get("gamma"));

    try std.testing.expect(!map.remove("nonexistent"));
    try std.testing.expectEqual(@as(usize, 2), map.count());
}

test "RobinHoodHashMap - string key empty strings" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap([]const u8, i32, StringContext(), 75).init(gpa, StringContext(){});
    defer map.deinit();

    try map.put("", 0);
    try std.testing.expectEqual(@as(?i32, 0), map.get(""));
    try std.testing.expect(map.contains(""));

    try std.testing.expect(map.remove(""));
    try std.testing.expect(!map.contains(""));
}

test "RobinHoodHashMap - string key similar strings" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap([]const u8, i32, StringContext(), 75).init(gpa, StringContext(){});
    defer map.deinit();

    try map.put("test", 1);
    try map.put("testing", 2);
    try map.put("tester", 3);
    try map.put("tes", 4);

    try std.testing.expectEqual(@as(?i32, 1), map.get("test"));
    try std.testing.expectEqual(@as(?i32, 2), map.get("testing"));
    try std.testing.expectEqual(@as(?i32, 3), map.get("tester"));
    try std.testing.expectEqual(@as(?i32, 4), map.get("tes"));
    try std.testing.expectEqual(@as(usize, 4), map.count());
}

test "RobinHoodHashMap - string key multiple operations" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap([]const u8, i32, StringContext(), 75).init(gpa, StringContext(){});
    defer map.deinit();

    try map.put("one", 1);
    try map.put("two", 2);
    try map.put("three", 3);
    try map.put("four", 4);
    try map.put("five", 5);

    try std.testing.expect(map.remove("two"));
    try std.testing.expect(map.remove("four"));

    try std.testing.expectEqual(@as(usize, 3), map.count());
    try std.testing.expect(map.contains("one"));
    try std.testing.expect(!map.contains("two"));
    try std.testing.expect(map.contains("three"));
    try std.testing.expect(!map.contains("four"));
    try std.testing.expect(map.contains("five"));

    try map.put("six", 6);
    try std.testing.expectEqual(@as(?i32, 6), map.get("six"));
    try std.testing.expectEqual(@as(usize, 4), map.count());
}

test "RobinHoodHashMap - string key remove and re-add" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap([]const u8, i32, StringContext(), 75).init(gpa, StringContext(){});
    defer map.deinit();

    try map.put("key", 100);
    try std.testing.expect(map.remove("key"));
    try std.testing.expect(!map.contains("key"));

    try map.put("key", 200);
    try std.testing.expectEqual(@as(?i32, 200), map.get("key"));
    try std.testing.expect(map.contains("key"));
}

test "RobinHoodHashMap - string key large dataset" {
    const gpa = std.testing.allocator;
    var map = try RobinHoodHashMap([]const u8, i32, StringContext(), 75).init(gpa, StringContext(){});
    defer map.deinit();

    var keys: std.ArrayList([]const u8) = .empty;
    try keys.ensureTotalCapacity(gpa, 100);
    defer {
        for (keys.items) |key| {
            gpa.free(key);
        }
        keys.deinit(gpa);
    }

    var i: i32 = 0;
    while (i < 50) : (i += 1) {
        const key = try std.fmt.allocPrint(gpa, "key_{d}", .{i});
        try keys.append(gpa, key);
        try map.put(key, i * 10);
    }

    try std.testing.expectEqual(@as(usize, 50), map.count());

    i = 0;
    while (i < 50) : (i += 1) {
        try std.testing.expectEqual(@as(?i32, i * 10), map.get(keys.items[@intCast(i)]));
    }

    i = 0;
    while (i < 25) : (i += 1) {
        try std.testing.expect(map.remove(keys.items[@intCast(i)]));
    }

    try std.testing.expectEqual(@as(usize, 25), map.count());

    i = 0;
    while (i < 25) : (i += 1) {
        try std.testing.expect(!map.contains(keys.items[@intCast(i)]));
    }

    i = 25;
    while (i < 50) : (i += 1) {
        try std.testing.expect(map.contains(keys.items[@intCast(i)]));
    }
}
