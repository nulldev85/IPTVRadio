import Foundation

/// Resolves the final URL of a stream endpoint that redirects, without
/// downloading the stream body.
///
/// Some providers redirect audio-only endpoints in ways AVPlayer refuses
/// (e.g. CFNetwork error 311), while a plain request follows them fine. The
/// app therefore resolves the endpoint itself and hands AVPlayer the final URL.
protocol StreamEndpointResolving: Sendable {
    func resolveFinalURL(for url: URL) async -> URL?
}

final class StreamRedirectResolver: NSObject, StreamEndpointResolving, URLSessionTaskDelegate, @unchecked Sendable {
    private let maxHops = 8
    private let timeout: TimeInterval = 5

    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL?, Never>?
    private var hops = 0
    private var resumed = false
    private var session: URLSession?

    func resolveFinalURL(for url: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

            lock.lock()
            self.session = session
            lock.unlock()

            var request = URLRequest(url: url)
            request.setValue("IPTVRadio/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
            session.dataTask(with: request).resume()
        }
    }

    private func finish(_ url: URL?) {
        lock.lock()
        guard !resumed else {
            lock.unlock()
            return
        }
        resumed = true
        let continuation = self.continuation
        let session = self.session
        self.continuation = nil
        self.session = nil
        lock.unlock()

        session?.invalidateAndCancel()
        continuation?.resume(returning: url)
    }

    // MARK: URLSessionTaskDelegate

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        hops += 1
        let exceeded = hops > maxHops
        lock.unlock()
        // Stop resolving when the chain loops; the caller falls back safely.
        completionHandler(exceeded ? nil : request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        // Headers are enough: cancel before any body is downloaded.
        completionHandler(.cancel)
        finish(response.url)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(nil)
    }
}
