//!
//! The zengine gfx error type
//!

pub const Error = error{
    GPUFailed,
    ImageFailed,
    ShaderFailed,
    WindowFailed,
    PipelineFailed,
    BufferFailed,
    MaterialFailed,
    SurfaceFailed,
    TextureFailed,
    SamplerFailed,
    CommandBufferFailed,
    CopyPassFailed,
    RenderPassFailed,
    DrawFailed,
    OutOfMemory,
};
