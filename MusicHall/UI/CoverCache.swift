import CoreImage
import UIKit

/// 封面图缓存：内存 NSCache + 同 URL 请求合并，列表滚动时不重复下载。
final class CoverCache {
    static let shared = CoverCache()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let lock = NSLock()
    private var pending: [String: [(UIImage?) -> Void]] = [:]

    private init() {
        cache.countLimit = 240
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    func cached(_ url: String) -> UIImage? {
        cache.object(forKey: url as NSString)
    }

    func load(_ url: String, completion: @escaping (UIImage?) -> Void) {
        if let hit = cached(url) {
            completion(hit)
            return
        }
        lock.lock()
        if var waiters = pending[url] {
            waiters.append(completion)
            pending[url] = waiters
            lock.unlock()
            return
        }
        pending[url] = [completion]
        lock.unlock()

        guard let link = URL(string: url) else {
            finish(url, image: nil)
            return
        }
        session.dataTask(with: link) { [weak self] data, _, _ in
            guard let self else { return }
            let image = data.flatMap { UIImage(data: $0) }
            if let image {
                self.cache.setObject(image, forKey: url as NSString)
            }
            self.finish(url, image: image)
        }.resume()
    }

    func image(for url: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            load(url) { image in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - 模糊背景

    /// 播放页背景用的「预模糊」小图。
    ///
    /// 直接对整屏封面做 `.blur(radius: 68)`，GPU 每帧都要重新卷积一遍，
    /// 是这台机器上异常发热的主因。这里改成：缩到 64×64 → Core Image 高斯模糊一次 →
    /// 结果缓存，界面只负责放大显示。放大后的双线性插值本身就是模糊的，
    /// 观感与实时模糊几乎一致，但渲染成本变成一张贴图。
    func backdrop(for url: String) async -> UIImage? {
        let key = "blur:" + url
        if let hit = cache.object(forKey: key as NSString) { return hit }
        guard let source = await image(for: url) else { return nil }
        let small = Self.blurredThumbnail(source)
        if let small { cache.setObject(small, forKey: key as NSString) }
        return small
    }

    private static let blurContext = CIContext(options: [.useSoftwareRenderer: false])

    private static func blurredThumbnail(_ image: UIImage, side: CGFloat = 64) -> UIImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = side / min(image.size.width, image.size.height)
        let target = CGSize(width: max(1, image.size.width * scale),
                            height: max(1, image.size.height * scale))

        let renderer = UIGraphicsImageRenderer(size: target)
        let thumb = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let cgImage = thumb.cgImage else { return nil }

        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return thumb }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(10, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return thumb }
        guard let result = blurContext.createCGImage(output, from: input.extent) else { return thumb }
        return UIImage(cgImage: result)
    }

    private func finish(_ url: String, image: UIImage?) {
        lock.lock()
        let waiters = pending.removeValue(forKey: url) ?? []
        lock.unlock()
        guard !waiters.isEmpty else { return }
        DispatchQueue.main.async {
            waiters.forEach { $0(image) }
        }
    }
}
