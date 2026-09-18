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

/// Stateless factory: every call runs in its own resolver object so concurrent
/// or repeated resolutions can never interfere with each other.
final class StreamRedirectResolver: StreamEndpointResolving, Sendable {
    private let maxHops: Int
    private let timeout: TimeInterval

    init(maxHops: Int = 8, timeout: TimeInterval = 5) {
        self.maxHops = maxHops
        self.timeout = timeout
    }

    func resolveFinalURL(for url: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            let run = RedirectRun(
                maxHops: maxHops,
                timeout: timeout,
                continuation: continuation
            )
            run.start(with: url)
        }
    }
}

/// One resolution attempt. All mutable state is owned by this object, which is
/// created per call.
private final class RedirectRun: NSObject, URLSessionTaskDelegate {
    private let maxHops: Int
    private let timeout: TimeInterval
    private let continuation: CheckedContinuation<URL?, Never>
    private var hops = 0
    private var finished = false
    private var session: URLSession?

    init(maxHops: Int, timeout: TimeInterval, continuation: CheckedContinuation<URL?, Never>) {
        self.maxHops = maxHops
        self.timeout = timeout
        self.continuation = continuation
    }

    func start(with url: URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session

        var request = URLRequest(url: url)
        request.setValue("IPTVRadio/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request).resume()
    }

    private func finish(_ url: URL?) {
        guard !finished else { return }
        finished = true
        let session = self.session
        self.session = nil
        session?.invalidateAndCancel()
        continuation.resume(returning: url)
    }

    // MARK: URLSessionTaskDelegate

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        hops += 1
        // Stop resolving when the chain loops; the caller falls back safely.
        completionHandler(hops > maxHops ? nil : request)
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
