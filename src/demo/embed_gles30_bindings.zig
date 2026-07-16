//! OpenGL ES declarations used only by the reference caller.
pub const gl = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GLES3/gl3.h");
    @cInclude("GLES2/gl2ext.h");
});
