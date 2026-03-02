# Robinhood HashMap 

Robinhood HashMap implementation in Zig

# Components

* Modules
  * robinhood-hashmap 
* Example usage
  * example

# Development

Zig target version: 0.15.2

```
# Build
zig build

# Run example
zig build run

# Test
zig build test --summary all
```

# Usage

## Install
```
zig fetch --save git+https://github.com/0x6a62/robinhood-hashmap.git
```

## Add to your `build.zig`
```
const robinhood-hashmap = b.dependency("robinhood_hashmap", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("robinhood_hashmap", robinhood_hashmap.module("robinhood_hashmap"));
```

## Using in code
```
// Import library
const robinhood-hashmap = @import("robinhood_hashmap");
```

# References

