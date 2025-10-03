```zig
//
//      7 o---------o 8
//       /|        /|
//      / |       / |
//   3 o---------o 4|
//     |  o------|--o 6
//     | / 5     | /
//     |/        |/
//   1 o---------o 2
//
```

# Zengine

A modern 3D game engine built in Zig using SDL3

## Installation

### Source code

Download the latest source files from [github](https://github.com/xgallom/zengine) and build with [Zig 0.15.1](https://ziglang.org/download/#release-0.15.1).
Zengine currently supports only target macos, builds of SDL for other platforms is not implemented yet.

```bash
git clone https://github.com/xgallom/zengine.git
cd zengine
zig build ext
zig build zengine
```

## License

A copy of the license is available in the [license file](LICENSE.md).
