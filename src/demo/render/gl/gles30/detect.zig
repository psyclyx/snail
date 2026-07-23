pub const Backend = enum { gles30 };

pub fn detect(gl: anytype) Backend {
    _ = gl;
    return .gles30;
}
