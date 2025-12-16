//!
//! The zengine gfx error type
//!

pub const Error = error{
    GPUFailed,
    FenceFailed,
    ImageFailed,
    TextEngineFailed,
    ShaderFailed,
    WindowFailed,
    PipelineFailed,
    BufferFailed,
    MaterialFailed,
    SurfaceFailed,
    TextureFailed,
    TransferBufferFailed,
    TextFailed,
    FontFailed,
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
