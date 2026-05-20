pub const Backend = enum { gles3 };

pub fn detect(gl: anytype) Backend {
    _ = gl;
    return .gles3;
}
