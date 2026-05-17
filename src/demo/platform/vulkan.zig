//! Demo-only Vulkan platform facade.
//! Windowed rendering and benchmark-only offscreen rendering keep separate
//! Vulkan state so they can be maintained independently.

pub const windowed = @import("vulkan/windowed.zig");
pub const offscreen = @import("vulkan/offscreen.zig");

pub const presentation = windowed.presentation;
pub const vk = windowed.vk;

pub const KEY_ESCAPE = windowed.KEY_ESCAPE;
pub const KEY_R = windowed.KEY_R;
pub const KEY_L = windowed.KEY_L;
pub const KEY_Z = windowed.KEY_Z;
pub const KEY_X = windowed.KEY_X;
pub const KEY_H = windowed.KEY_H;
pub const KEY_B = windowed.KEY_B;
pub const KEY_LEFT = windowed.KEY_LEFT;
pub const KEY_RIGHT = windowed.KEY_RIGHT;
pub const KEY_UP = windowed.KEY_UP;
pub const KEY_DOWN = windowed.KEY_DOWN;

pub const init = windowed.init;
pub const initForWindow = windowed.initForWindow;
pub const consumeMonitorChanged = windowed.consumeMonitorChanged;
pub const detectCurrentMonitorSubpixelOrder = windowed.detectCurrentMonitorSubpixelOrder;
pub const deinit = windowed.deinit;
pub const beginFrame = windowed.beginFrame;
pub const currentFrameIndex = windowed.currentFrameIndex;
pub const endFrame = windowed.endFrame;
pub const shouldClose = windowed.shouldClose;
pub const getWindowSize = windowed.getWindowSize;
pub const getFramebufferSize = windowed.getFramebufferSize;
pub const presentationInfo = windowed.presentationInfo;
pub const swapchainEncoding = windowed.swapchainEncoding;
pub const getTime = windowed.getTime;
pub const isKeyDown = windowed.isKeyDown;
pub const isKeyPressed = windowed.isKeyPressed;

pub const initOffscreen = offscreen.initOffscreen;
pub const physicalDeviceName = offscreen.physicalDeviceName;
pub const deinitOffscreen = offscreen.deinitOffscreen;
pub const beginFrameOffscreen = offscreen.beginFrameOffscreen;
pub const beginFrameOffscreenWithClear = offscreen.beginFrameOffscreenWithClear;
pub const currentOffscreenFrameIndex = offscreen.currentOffscreenFrameIndex;
pub const endFrameOffscreen = offscreen.endFrameOffscreen;
pub const captureOffscreenRgba8 = offscreen.captureOffscreenRgba8;

/// Block until all GPU work submitted through either demo Vulkan path is complete.
pub fn queueWaitIdle() void {
    windowed.queueWaitIdle();
    offscreen.queueWaitIdle();
}
