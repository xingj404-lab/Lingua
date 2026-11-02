import AppKit
import ImageIO
import Vision
import TranslationCore

struct OCRResult: Sendable {
    let text: String
    let lowConfidenceLines: Int
    let previewData: Data?
}

struct OCRService: Sendable {
    func recognize(url: URL) async throws -> OCRResult {
        try await Task.detached(priority: .userInitiated) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber, size.intValue > 40_000_000 {
                throw TranslationError.backend("图片超过 40 MB，请缩小后导入。")
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw TranslationError.backend("无法读取图片，请使用 PNG、JPEG、HEIC 或 TIFF。")
            }
            // Thumbnail decoding bounds memory and applies EXIF orientation before recognition.
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                           kCGImageSourceThumbnailMaxPixelSize: 4096,
                                           kCGImageSourceCreateThumbnailWithTransform: true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw TranslationError.backend("图片解码失败。")
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR", "fr-FR", "de-DE", "es-ES"]
            try VNImageRequestHandler(cgImage: image).perform([request])
            try Task.checkCancellation()
            let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
            guard !candidates.isEmpty else { throw TranslationError.backend("未识别到文字，请换用清晰、正向的图片。") }
            let previewOptions: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 600, kCGImageSourceCreateThumbnailWithTransform: true]
            var previewData: Data?
            if let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, previewOptions as CFDictionary) {
                let bytes = NSMutableData()
                if let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, preview, nil)
                    if CGImageDestinationFinalize(destination) { previewData = bytes as Data }
                }
            }
            return OCRResult(text: candidates.map(\.string).joined(separator: "\n"),
                             lowConfidenceLines: candidates.filter { $0.confidence < 0.7 }.count,
                             previewData: previewData)
        }.value
    }
}
