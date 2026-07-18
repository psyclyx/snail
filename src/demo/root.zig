const entry = switch (@import("demo_entry").value) {
    .banner => @import("app/banner.zig"),
    .game => @import("app/game.zig"),
    .autohint_compare => @import("autohint/compare.zig"),
    .autohint_character_diff => @import("tools/autohint/character_diff.zig"),
    .autohint_diff => @import("tools/autohint/diff.zig"),
    .autohint_proportional => @import("tools/autohint/proportional.zig"),
    .autohint_screenshot => @import("tools/autohint/screenshot.zig"),
    .backend_compare => @import("tools/compare/backends.zig"),
    .composite_probe => @import("tools/probes/composite.zig"),
    .coverage_probe => @import("tools/probes/coverage.zig"),
    .gamma_probe => @import("tools/probes/gamma.zig"),
    .screenshot_cpu => @import("tools/screenshots/cpu.zig"),
    .screenshot_gl => @import("tools/screenshots/gl.zig"),
    .screenshot_gles30 => @import("tools/screenshots/gles30.zig"),
    .screenshot_vulkan => @import("tools/screenshots/vulkan.zig"),
    .banner_screenshot_cpu => @import("tools/screenshots/banner_cpu.zig"),
    .banner_screenshot_gl => @import("tools/screenshots/banner_gl.zig"),
    .banner_screenshot_gles30 => @import("tools/screenshots/banner_gles30.zig"),
    .banner_screenshot_vulkan => @import("tools/screenshots/banner_vulkan.zig"),
    .game_screenshot_gl => @import("tools/screenshots/game_gl.zig"),
    .game_screenshot_vulkan => @import("tools/screenshots/game_vulkan.zig"),
};

pub fn main() !void {
    return entry.main();
}

test {
    _ = entry;
}
