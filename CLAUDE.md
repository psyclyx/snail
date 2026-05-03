# snail

GPU font rendering via Slug algorithm (direct Bézier curve evaluation in fragment shader).

## Build

```sh
nix-shell
zig build run       # demo
zig build test      # tests
zig build bench     # benchmarks
```

## Architecture

- `src/snail.zig` — public API: Font, Atlas, Renderer, Batch
- `src/font/ttf.zig` — TTF parser
- `src/math/` — Vec2, Mat4, QuadBezier, quadratic root solver
- `src/render/` — GLSL shaders, OpenGL pipeline, curve/band textures, vertex gen
- `src/profile/` — comptime-gated CPU timers
- `assets/` — bundled NotoSans-Regular.ttf, screenshots

## Conventions

- Zig 0.16: `ArrayList` uses `.empty` init, allocator per method. No `std.time.Instant` (use libc `clock_gettime`). No `std.io` (use `std.Io` or `std.debug.print`). No GPA (use `DebugAllocator`).
- GLSL shaders embedded as Zig multiline strings (`\\` prefix).
- Column-major matrices (OpenGL convention). HLSL→GLSL: extract rows manually from `mat4`.
- Band texture width fixed at 4096 (`kLogBandTextureWidth = 12`).
- Colors: sRGB, straight alpha, `[4]f32` 0.0–1.0. Images are sRGB RGBA8. Gradients interpolate in sRGB. Blending is gamma-correct (linear-space compositing).
