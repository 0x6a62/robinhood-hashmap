// Example Usage

const std = @import("std");
const rbhm = @import("robinhood_hashmap");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const RobinHoodHashMap = rbhm.RobinHoodHashMap;
const AutoContext = rbhm.AutoContext;
const StringContext = rbhm.StringContext;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // numeric key
    {
        var hashmap = try RobinHoodHashMap(i32, i32, AutoContext(i32), 80).init(allocator, .{});
        defer hashmap.deinit();

        const data = [_]i32{ 10, 20, 30, 20, 20, 10, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130 };
        for (data) |datum| {
            try hashmap.put(datum, datum + 1000);
        }

        var iter = hashmap.iterator();
        while (iter.next()) |entry| {
            print("{d:<20} = {d:10}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    // string key
    {
        var hashmap = try RobinHoodHashMap([]const u8, usize, StringContext(), 80).init(allocator, .{});
        defer hashmap.deinit();

        const data = [_][]const u8{ "10", "20", "30", "40", "50", "60", "10", "10", "10" };
        for (0.., data) |i, datum| {
            try hashmap.put(datum, i);
        }

        var iter = hashmap.iterator();
        while (iter.next()) |entry| {
            print("{s:<20} = {d:10}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    print("done\n", .{});
}
