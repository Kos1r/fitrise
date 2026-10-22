import UIKit

/// Downscales meal photos (~1024 px long edge) and JPEG-compresses them before upload.
enum ImageProcessor {
    static func preparedJPEG(from image: UIImage, maxDimension: CGFloat = AppConfig.imageMaxDimension, quality: CGFloat = AppConfig.imageJPEGQuality) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    static func preparedJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return preparedJPEG(from: image)
    }
}
