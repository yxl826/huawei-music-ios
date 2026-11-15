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
