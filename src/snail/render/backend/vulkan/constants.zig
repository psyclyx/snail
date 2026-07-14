const vertex = @import("snail_core").files.format_vertex;

// Partition the persistently mapped upload buffer by frame slot so a frame can
// suballocate monotonically without overwriting earlier draws before submit.
pub const UPLOAD_SLOTS = 8;
pub const UPLOAD_SLOT_BYTES = 8 * 1024 * 1024; // 8 MB per frame slot
pub const RING_TOTAL_BYTES = UPLOAD_SLOTS * UPLOAD_SLOT_BYTES;
pub const BYTES_PER_GLYPH = vertex.BYTES_PER_INSTANCE;
pub const MAX_GLYPHS_PER_FRAME = UPLOAD_SLOT_BYTES / BYTES_PER_GLYPH;
