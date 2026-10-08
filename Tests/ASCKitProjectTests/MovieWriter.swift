import AVFoundation
import CoreVideo
import Foundation

/// Writes small real movies for the tests, so the reader is checked against
/// what AVFoundation makes and not against bytes made to agree with it.
enum MovieWriter {
    struct Options {
        var width = 64
        var height = 128
        var seconds = 16.0
        var fps = 30.0
        var codec: AVVideoCodecType = .h264
        var fileType: AVFileType = .mov
        var turned = false
        /// Frame times that wander, as a screen recording's do.
        var variableFrameRate = false
    }

    static func write(to url: URL, _ options: Options = Options()) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: options.fileType)

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: options.codec,
            AVVideoWidthKey: options.width,
            AVVideoHeightKey: options.height
        ])
        input.expectsMediaDataInRealTime = false
        if options.turned { input.transform = CGAffineTransform(rotationAngle: .pi / 2) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: options.width,
            kCVPixelBufferHeightKey as String: options.height
        ])
        writer.add(input)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frames = Int(options.seconds * options.fps)
        for index in 0 ... frames {
            try await waitForRoom(input)
            var seconds = Double(index) / options.fps
            if options.variableFrameRate, index > 0, index < frames, index % 3 == 0 {
                seconds += 0.4 / options.fps
            }
            let buffer = try pixelBuffer(pool: adaptor.pixelBufferPool, width: options.width, height: options.height)
            adaptor.append(buffer, withPresentationTime: CMTime(seconds: seconds, preferredTimescale: 6000))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }

    private static func pixelBuffer(pool: CVPixelBufferPool?, width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        } else {
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        }
        guard let buffer else { throw CocoaError(.featureUnsupported) }
        return buffer
    }

    /// Gives up after five seconds rather than hanging the whole run.
    private static func waitForRoom(_ input: AVAssetWriterInput) async throws {
        var waited = 0
        while input.isReadyForMoreMediaData == false {
            waited += 1
            guard waited < 5000 else { throw CocoaError(.fileWriteUnknown) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}
