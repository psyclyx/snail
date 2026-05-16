const atlas_curve_mod = @import("renderer/atlas/curve.zig");
const atlas_page_mod = @import("renderer/atlas/page.zig");
const resources_view_mod = @import("resources/view.zig");
const text_mod = @import("text.zig");
const texture_layers = @import("renderer/texture_layers.zig");

pub const TEXT_WORDS_PER_VERTEX = text_mod.TEXT_WORDS_PER_VERTEX;
pub const TEXT_VERTICES_PER_GLYPH = text_mod.TEXT_VERTICES_PER_GLYPH;
pub const TEXT_WORDS_PER_GLYPH = text_mod.TEXT_WORDS_PER_GLYPH;

pub const TEXTURE_LAYER_WINDOW_SIZE = texture_layers.WINDOW_SIZE;
pub const TEXTURE_LAYER_BANK_STRIDE = texture_layers.BANK_STRIDE;
pub const textureLayerBank = texture_layers.bank;
pub const textureLayerBankLocal = texture_layers.bankLocal;
pub const textureLayerInBank = texture_layers.inBank;
pub const textureLayerWindowBase = texture_layers.windowBase;
pub const textureLayerLocal = texture_layers.local;

pub const AtlasPage = atlas_page_mod.AtlasPage;
pub const CurveAtlas = atlas_curve_mod.CurveAtlas;
pub const Atlas = atlas_curve_mod.Atlas;

pub const PreparedTextAtlasView = resources_view_mod.PreparedTextAtlasView;
pub const PreparedImageView = resources_view_mod.PreparedImageView;
pub const PreparedAtlasView = resources_view_mod.PreparedAtlasView;
pub const PreparedLayerInfoUpload = resources_view_mod.PreparedLayerInfoUpload;
pub const PreparedLayerInfoView = resources_view_mod.PreparedLayerInfoView;
pub const coerceAtlasHandle = resources_view_mod.coerceAtlasHandle;

pub const TextBatch = text_mod.TextBatch;
