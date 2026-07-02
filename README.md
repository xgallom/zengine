```
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

3D game engine in Zig, on SDL3 GPU. macOS only, target Zig 0.15.2.

## Build

External dependencies (SDL3, SDL3_image, SDL3_ttf, SDL3_shadercross, cimgui, cimplot) are built from source once, then linked as system libraries.

```sh
git clone https://github.com/xgallom/zengine.git
cd zengine
zig build ext -Doptimize=ReleaseFast
zig build zengine -Doptimize=ReleaseFast
./zig-out/bin/zengine
```

`zig build ext` accepts `-Dext-command=<step>` to build one dependency at a time instead of all of them: `external`, `cache`, `sdl`, `sdl_image`, `sdl_ttf`, `shadercross`, `cimgui`, `cimplot`. `zig build ext-clean` removes the built artifacts for the selected step.

Windows: builds up to the DirectXShaderCompiler step; that step does not yet build under MinGW.

## Use as a dependency

```zig
// build.zig.zon
.dependencies = .{
    .zengine = .{ .path = "../zengine" },
},
```

```zig
// build.zig
const zengine = b.dependency("zengine", .{});
const z = @import("zengine");
const options = z.getOptions(b);
// ...

exe.root_module.addImport("zengine", zengine.module("zengine"));
```

A consuming `build.zig` also needs to call `addCompileShaders` (exported from zengine's `build.zig`) to compile its own `.hlsl` shaders through `SDL_shadercross`, and depend on zengine's own shader install step for the shaders zengine ships with (bloom, etc). This workflow also allows for dynamic translation of arbitrary game shaders, by adding a custom `addCompileShaders` step:

```zig
// Install required Zengine shaders:
    {
        const install_shaders_dir = try z.addCompileShaders(b, .{
            .b = zengine.builder,
            .module = zengine.module("zengine"),
            .options = options,
            .optimize = optimize,
        });
        b.getInstallStep().dependOn(&install_shaders_dir.step);
    }

// Install custom game shaders:
    {
        const install_shaders_dir = try z.addCompileShaders(b, .{
            .b = zengine.builder,
            .src = b.path("shaders"),
            .module = zengine.module("zengine"),
            .options = options,
            .optimize = optimize,
        });
        b.getInstallStep().dependOn(&install_shaders_dir.step);
    }
```

## Entry point

An application implements a subset of `Zengine.Handlers` and calls `Zengine.create`/`.run`:

```zig
const zengine = @import("zengine");
const Zengine = zengine.Zengine;

pub fn main() !void {
    zengine.allocators.init(1_000_000_000);
    defer zengine.allocators.deinit();

    var engine = try Zengine.create(.{
        .register = &register, // register ECS component types
        .load = &load,         // load GPU resources, return false to abort
        .unload = &unload,
        .input = &input,        // return false to quit
        .update = &update,      // return false to quit
        .render = &render,
    });
    defer engine.deinit();
    return engine.run();
}
```

`Zengine.createHeadless` skips window/renderer/scene/UI setup for tools that only need the allocator, scheduler, and filesystem layer (see `src/compile_shaders.zig`).

Compile-time `zengine_options: zengine.Options` on the root file toggles `has_renderer`, `has_scene`, `has_ui`, `has_debug_ui`, `log_allocations`, and graphics defaults (default material, normal smoothing).

## Modules

| module | holds |
|---|---|
| `allocators` | arena/pool allocators used by every other module; global, frame, scratch, gpa lifetimes |
| `global` | per-frame state: args, paths, frame index, timing |
| `Engine` / `Window` | SDL window + properties |
| `Event` | SDL event poll wrapper |
| `gfx` | GPU device, pipelines, buffers, textures, `Renderer`, `Scene`, `Loader`, mesh/obj/mtl/lgh/ttf loaders, render passes (`gfx/pass`) |
| `ecs` | component storage (array-list and pool-backed), component manager, flags bitset |
| `ui` | ImGui-backed debug windows (allocations, perf, log, property editor) |
| `math` | scalar/vector/matrix/quaternion types, batch operations |
| `containers` | key-indexed maps (`key_map`), `key_tree_map`, `radix_tree`, `tree`, `swap_wrapper` |
| `perf` | frame-section timing tree, stats, graph |
| `scheduler` | task list, `Promise(T)` |
| `anim` | `lerp`, `smv` (smooth-move) interpolation |
| `controls` | bitset-backed input state for an arbitrary key enum |
| `str`, `fs`, `time`, `type_id`, `error`, `ext` | string helpers, file IO, SDL time, type-id tags, error sets, C imports |

## Frame loop

`Zengine.run` drives, per frame: `input -> update -> render`, wrapped in `perf` sections (`main.init`, `main.frame.{init,input,update,render}`), with frame-scoped allocations released after each frame (`allocators.frameReset()`). Returning `false` from `input` or `update` stops the loop.

## GPU rendering

`gfx.Renderer` wraps an `SDL_GPUDevice`. `gfx.Loader` uploads meshes/textures/fonts/LUTs and returns handles used by `gfx.Scene` and by direct `SurfaceTexture` access (see `z-chip`'s custom emulator-screen texture for an example of writing directly into a loaded surface). Shaders are `.hlsl`, cross-compiled by `SDL_shadercross`; `addCompileShaders` in `build.zig` wires that step into any build.

## Tests

```sh
zig build test
```

## License

zlib, see [LICENSE.md](LICENSE.md).
