pub const Backend = enum { gl33, gl44 };

pub fn detect(gl: anytype) Backend {
    const ver = gl.glGetString(gl.GL_VERSION) orelse return .gl33;
    if (ver[0] < '0' or ver[0] > '9') return .gl33;
    if (ver[2] < '0' or ver[2] > '9') return .gl33;
    const major = ver[0] - '0';
    const minor = ver[2] - '0';
    if (major > 4 or (major == 4 and minor >= 4)) return .gl44;
    return .gl33;
}
