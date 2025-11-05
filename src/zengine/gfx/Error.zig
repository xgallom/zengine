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
    TransferBufferFailed,
    SamplerFailed,
    LightFailed,
    CameraFailed,
    CommandBufferFailed,
    RenderPassFailed,
    ComputePassFailed,
    CopyPassFailed,
    DrawFailed,
    OutOfMemory,
};
