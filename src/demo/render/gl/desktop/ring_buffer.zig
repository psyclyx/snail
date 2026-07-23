//! Persistent-mapped streaming ring buffer for the GL 4.4 backend.
//!
//! GL 4.4 lets us map a single VBO `GL_MAP_PERSISTENT_BIT |
//! GL_MAP_COHERENT_BIT` and write into it from the CPU while the GPU
//! reads from prior offsets. The ring divides that storage into N
//! segments; each frame, the writer advances to the next segment so
//! the GPU is never reading and writing the same bytes. A `glFenceSync`
//! at the end of every dirtied segment lets us block on first reuse
//! without serializing the rest.
//!
//! The buffer is allocated on a caller-owned VBO; the caller is
//! responsible for binding the VBO as a vertex source. The reserve /
//! commit API hands back absolute byte offsets so callers can issue
//! `glVertexArrayVertexBuffer(..., offset, ...)`.

const gl = @import("bindings.zig").gl;

pub const SEGMENTS: u32 = 3;
pub const TOTAL_BYTES: usize = 12 * 1024 * 1024; // 12 MB (4 MB per segment)
pub const SEGMENT_BYTES: usize = TOTAL_BYTES / SEGMENTS;

pub const RingBuffer = struct {
    map: ?[*]u8 = null,
    fences: [SEGMENTS]gl.GLsync = .{null} ** SEGMENTS,
    segment: u32 = 0,
    offset: usize = 0,
    segment_dirty: [SEGMENTS]bool = .{false} ** SEGMENTS,

    /// Allocate persistent-mapped storage on `vbo`. Returns
    /// `error.UnsupportedOpenGlBackend` if the driver refuses to map.
    pub fn init(self: *RingBuffer, vbo: gl.GLuint) !void {
        const flags: gl.GLbitfield = gl.GL_MAP_WRITE_BIT | gl.GL_MAP_PERSISTENT_BIT | gl.GL_MAP_COHERENT_BIT;
        gl.glNamedBufferStorage(vbo, TOTAL_BYTES, null, flags);
        self.map = @ptrCast(gl.glMapNamedBufferRange(vbo, 0, TOTAL_BYTES, flags));
        if (self.map == null) return error.UnsupportedOpenGlBackend;
    }

    pub fn deinit(self: *RingBuffer, vbo: gl.GLuint) void {
        for (&self.fences) |*f| {
            if (f.*) |fence| {
                gl.glDeleteSync(fence);
                f.* = null;
            }
        }
        if (self.map != null) {
            _ = gl.glUnmapNamedBuffer(vbo);
            self.map = null;
        }
    }

    /// Called at the start of each frame: if the current segment was
    /// written to last frame, fence it and advance so the next reserve
    /// lands in a fresh segment.
    pub fn beginFrame(self: *RingBuffer) void {
        if (!self.segment_dirty[self.segment]) return;
        self.fenceCurrent();
        self.segment = (self.segment + 1) % SEGMENTS;
        self.offset = 0;
    }

    /// Reserve up to `requested_bytes` worth of room in the ring,
    /// rounded down to the nearest `granularity` boundary. Advances to
    /// the next segment if the current one can't fit one full
    /// granularity unit, waiting on the next segment's fence if it was
    /// dirtied by a prior frame.
    ///
    /// Returns the absolute byte offset to write into and the number of
    /// bytes actually granted (`<= requested_bytes`, multiple of
    /// `granularity`).
    pub fn reserve(self: *RingBuffer, requested_bytes: usize, granularity: usize) struct { offset: usize, bytes: usize } {
        if (SEGMENT_BYTES - self.offset < granularity) {
            self.advance();
        } else {
            self.waitSegment(self.segment);
        }
        const segment_capacity = (SEGMENT_BYTES - self.offset) / granularity * granularity;
        const bytes = @min(requested_bytes, segment_capacity);
        const offset = @as(usize, self.segment) * SEGMENT_BYTES + self.offset;
        return .{ .offset = offset, .bytes = bytes };
    }

    /// Mark `bytes` as consumed in the current segment.
    pub fn commit(self: *RingBuffer, bytes: usize) void {
        self.offset += bytes;
        self.segment_dirty[self.segment] = true;
    }

    fn advance(self: *RingBuffer) void {
        self.fenceCurrent();
        self.segment = (self.segment + 1) % SEGMENTS;
        self.offset = 0;
        self.waitSegment(self.segment);
    }

    fn fenceCurrent(self: *RingBuffer) void {
        if (!self.segment_dirty[self.segment]) return;
        self.fences[self.segment] = gl.glFenceSync(gl.GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
        self.segment_dirty[self.segment] = false;
    }

    fn waitSegment(self: *RingBuffer, segment: u32) void {
        if (self.fences[segment]) |fence| {
            const status = gl.glClientWaitSync(fence, 0, 0);
            if (status != gl.GL_ALREADY_SIGNALED and status != gl.GL_CONDITION_SATISFIED) {
                _ = gl.glClientWaitSync(fence, gl.GL_SYNC_FLUSH_COMMANDS_BIT, 1_000_000_000);
            }
            gl.glDeleteSync(fence);
            self.fences[segment] = null;
        }
    }
};
