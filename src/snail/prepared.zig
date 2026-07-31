//! Data-oriented, transport-agnostic prepared producer artifacts.
//!
//! Values separate expensive preparation from atlas identity and presentation.
//! Archives are immutable borrowed views over caller-provided bytes: mapping,
//! reading, embedding, streaming into a retained buffer, and persistence policy
//! all remain the caller's choice.

const key = @import("prepared/key.zig");
const value = @import("prepared/value.zig");
const archive = @import("prepared/archive.zig");

pub const producer_version = key.producer_version;
pub const FontKey = key.FontKey;
pub const GeometrySourceKey = key.GeometrySourceKey;
pub const Key = key.Key;
pub const GeometryOptions = key.GeometryOptions;
pub const AutohintOptions = key.AutohintOptions;
pub const unhintedKey = key.unhintedKey;
pub const geometryKey = key.geometryKey;
pub const autohintModelKey = key.autohintModelKey;
pub const autohintGlyphKey = key.autohintGlyphKey;
pub const ttGlyphKey = key.ttGlyphKey;
pub const ttAdvanceKey = key.ttAdvanceKey;

pub const GeometryView = value.GeometryView;
pub const Geometry = value.Geometry;
pub const AutohintModelView = value.AutohintModelView;
pub const AutohintGlyphView = value.AutohintGlyphView;
pub const TtGlyphView = value.TtGlyphView;
pub const ValueView = value.ValueView;
pub const RecordView = value.RecordView;
pub const OwnedValue = value.OwnedValue;
pub const OwnedRecord = value.OwnedRecord;
pub const Archive = archive.Archive;
pub const ArchiveBuilder = archive.ArchiveBuilder;
pub const OwnedArchive = archive.OwnedArchive;
pub const ArchiveOpenError = archive.OpenError;
pub const ArchiveBuildError = archive.BuildError;
pub const archive_format_version = archive.format_version;

test {
    _ = key;
    _ = value;
    _ = archive;
}
