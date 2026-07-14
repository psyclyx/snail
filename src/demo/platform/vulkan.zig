//! Demo-only offscreen Vulkan facade used by the Vulkan screenshot demo.

pub const offscreen = @import("vulkan/offscreen.zig");

pub const initOffscreen = offscreen.initOffscreen;
pub const physicalDeviceName = offscreen.physicalDeviceName;
pub const deinitOffscreen = offscreen.deinitOffscreen;
pub const beginFrameOffscreen = offscreen.beginFrameOffscreen;
pub const beginFrameOffscreenWithClear = offscreen.beginFrameOffscreenWithClear;
pub const currentOffscreenFrameIndex = offscreen.currentOffscreenFrameIndex;
pub const OFFSCREEN_FRAMES_IN_FLIGHT = offscreen.OFFSCREEN_FRAMES_IN_FLIGHT;
pub const endFrameOffscreen = offscreen.endFrameOffscreen;
pub const captureOffscreenRgba8 = offscreen.captureOffscreenRgba8;
pub const queueWaitIdle = offscreen.queueWaitIdle;
