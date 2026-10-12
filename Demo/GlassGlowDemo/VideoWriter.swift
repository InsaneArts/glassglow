import AVFoundation
import CoreImage

/// Writes frames to a movie file.
final class VideoWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let fps: Int32
    private var frames: Int64 = 0

    /// H.264 in an .mp4 for sharing, or ProRes 422 HQ in a .mov as a master for editing.
    init(url: URL, width: Int, height: Int, fps: Int, master: Bool = false) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: master ? .mov : .mp4)
        var settings: [String: Any] = [
            AVVideoCodecKey: master ? AVVideoCodecType.proRes422HQ : AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        if !master {
            settings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: width * height * fps / 6,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ]
        }
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        self.fps = Int32(fps)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
    }

    /// Appends the next frame, drawn into a pixel buffer by `draw`.
    func append(_ draw: (CVPixelBuffer) -> Void) {
        guard let pool = adaptor.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        draw(buffer)
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        adaptor.append(buffer, withPresentationTime: CMTime(value: frames, timescale: fps))
        frames += 1
    }

    func finish() {
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
    }
}
