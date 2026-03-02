# Robinhood HashMap 

Robinhood HashMap implementation in Zig

# Components

* Modules
  * robinhoodhashmap 
* Example usage
  * example

# Development

Zig target version: 0.15.2

```
# Build
zig build

# Run
zig build run

# Test
zig build test --summary all
```

# Usage

## Install
```
zig fetch --save git+https://github.com/0x6a62/robinhoodhashmap-zig.git
```

## Add to your `build.zig`
```
const robinhoodhashmap = b.dependency("robinhoodhashmap", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("robinhoodhashmap", robinhoodhashmap.module("robinhoodhashmap"));
```

## Using in code
```
// Import library
const robinhoodhashmap = @import("robinhoodhashmap");
```

# References

