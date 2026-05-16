pub const WINDOW_SIZE: u32 = 255;
pub const BANK_STRIDE: u32 = WINDOW_SIZE * 65536;

pub fn bank(layer: u32) u32 {
    return layer / BANK_STRIDE;
}

pub fn bankLocal(layer: u32) u32 {
    return layer % BANK_STRIDE;
}

pub fn inBank(bank_id: u32, layer: u32) u32 {
    return bank_id * BANK_STRIDE + layer;
}

pub fn windowBase(layer: u32) u32 {
    const bank_base = layer - bankLocal(layer);
    const offset = bankLocal(layer);
    return bank_base + (offset / WINDOW_SIZE) * WINDOW_SIZE;
}

pub fn local(layer: u32) !u8 {
    const base = windowBase(layer);
    const offset = layer - base;
    if (offset >= WINDOW_SIZE) return error.TextureLayerWindowOverflow;
    return @intCast(offset);
}
