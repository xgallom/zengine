//!
//! The zengine audio error type
//!

pub const Error = error{
    MixerFailed,
    AudioFailed,
    TrackFailed,
};
