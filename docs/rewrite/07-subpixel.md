# Subpixel rendering

Subpixel coverage (LCD striping) is supported but rare and slow. The design
keeps it out of the API hot path and makes it a draw-state toggle.

## Where it lives

```zig
pub const DrawState = struct {
    mvp:     Mat4,
    surface: TargetSurface,
    raster:  RasterOptions = .{},
};

pub const RasterOptions = struct {
    subpixel_order:   SubpixelOrder = .none,    // .none, .rgb, .bgr, .vrgb, .vbgr
    fill_rule:        FillRule       = .non_zero,
    coverage_transfer: CoverageTransfer = .identity,
};
```

The `subpixel_order` field selects between shader programs at draw time.
There are two coverage shader variants per backend:
- **Greyscale**: one sample per pixel.
- **Subpixel**: three or six samples per pixel along the stripe axis,
  filtered into per-channel coverage.

The backends compile both at build time. `renderer.draw()` looks at
`state.raster.subpixel_order` and binds the appropriate program for the
duration of the draw.

## Why it's not a segment-level concern

Subpixel mode is a property of the *output target*, not of any one shape.
A given frame either uses LCD coverage for all its text or it doesn't.
Mixing within a frame is unusual and provided implicitly by issuing
multiple `draw()` calls with different `DrawState`s.

Compare to the heterogeneous-vs-replicated distinction (see
[03-picture-and-emit.md](03-picture-and-emit.md)), which *is* per-segment
because different *shapes* in the same frame want different code paths.
Subpixel is per-frame.

## Performance characteristics

The subpixel fragment shader is significantly slower than greyscale:
- 3× more coverage evaluations along the stripe axis
- Larger filter kernel application
- More instruction count

Callers that don't need LCD striping (most modern UIs with hidpi
displays) should leave `subpixel_order = .none` and pay the greyscale cost.

## Build-time toggle

The subpixel shader variant can be disabled at build time for callers who
never use it:

```zig
const snail_mod = b.dependency("snail", .{
    .target = target,
    .optimize = optimize,
    .subpixel = false,    // omit the subpixel shader programs entirely
}).module("snail");
```

When disabled, setting `subpixel_order` to anything other than `.none`
returns `error.SubpixelNotEnabled` at draw time.

## Custom-shader implications

A custom-shader user who wants subpixel coverage in their own shader picks
the corresponding helper from `snail.shader.glsl.coverage_subpixel`. The
helper is a string constant they include in their own GLSL source. The
internal shader does the same — there's no privileged subpixel path.
