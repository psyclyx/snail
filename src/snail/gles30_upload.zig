//! GLES3 prepared-pages cache: a thin alias over the unified
//! `gl_upload.GlPreparedPagesFor(.gles30)`.

const gl_upload = @import("gl_upload.zig");

pub const Gles30PreparedPages = gl_upload.GlPreparedPagesFor(.gles30);
