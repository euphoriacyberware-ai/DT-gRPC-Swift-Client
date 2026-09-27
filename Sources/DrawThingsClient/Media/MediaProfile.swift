//
//  MediaProfile.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation

/// Media properties of a generation's output, derived from its configuration and model.
public struct MediaProfile: Sendable, Hashable {
    /// The model family used to decode previews.
    public var family: ModelFamily
    /// True when the output is a video: a video model generating more than one frame.
    public var isVideo: Bool
    /// Frames per second for video output, or nil for image models.
    public var frameRate: Int?
    /// Sample rate of generated audio, or nil when the model doesn't generate audio.
    public var audioSampleRate: Double?

    public init(family: ModelFamily, isVideo: Bool, frameRate: Int?, audioSampleRate: Double?) {
        self.family = family
        self.isVideo = isVideo
        self.frameRate = frameRate
        self.audioSampleRate = audioSampleRate
    }

    /// Resolves the profile for a configuration.
    ///
    /// - Parameters:
    ///   - configuration: The generation configuration.
    ///   - family: Overrides the family detected from `configuration.model`.
    ///   - audioSampleRate: Overrides the family's audio sample rate (for example from server
    ///     model metadata).
    public init(configuration: DrawThingsConfiguration, family: ModelFamily? = nil, audioSampleRate: Double? = nil) {
        let family = family ?? ModelFamily.detect(from: configuration.model)
        self.family = family
        self.frameRate = family.nativeFrameRate
        // numFrames defaults to 14 for every configuration, so only a video model counts.
        self.isVideo = family.nativeFrameRate != nil && configuration.numFrames > 1
        self.audioSampleRate = audioSampleRate ?? family.audioSampleRate
    }
}
