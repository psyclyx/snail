const core = @import("core.zig");

pub const GlBindings = core.GlCoverageBindings;
pub const VulkanBindings = core.VulkanCoverageBindings;
pub const Bindings = core.CoverageBindings;
pub const Shader = core.CoverageShader;
pub const GlProgram = core.GlCoverageProgram;
pub const VulkanProgram = core.VulkanCoverageProgram;
pub const CpuProgram = core.CpuCoverageProgram;
pub const Program = core.CoverageProgram;
pub const GlBackend = core.GlCoverageBackend;
pub const VulkanBackend = core.VulkanCoverageBackend;
pub const Backend = core.CoverageBackend;

pub const TextCoverageBindings = core.TextCoverageBindings;
pub const TextCoverageShader = core.TextCoverageShader;
pub const TextCoverageOptions = core.TextCoverageOptions;
pub const TextCoverageRecords = core.TextCoverageRecords;
pub const TextCoverageBackend = core.TextCoverageBackend;
