import XCTest
@testable import IPTVRadio

final class StreamRedirectResolverTests: XCTestCase {
    /// Regression: the resolver previously kept mutable run state on the shared
    /// instance, so every call after the first hung forever — which blocked
    /// playback entirely after switching stations.
    func testResolverCanBeUsedRepeatedly() async {
        let resolver = StreamRedirectResolver(timeout: 2)
        let deadURL = URL(string: "http://127.0.0.1:1/unreachable.mp3")!

        let first = await resolver.resolveFinalURL(for: deadURL)
        XCTAssertNil(first)

        let second = await resolver.resolveFinalURL(for: deadURL)
        XCTAssertNil(second, "A second resolution must complete instead of hanging")
    }

    func testConcurrentResolutionsDoNotInterfere() async {
        let resolver = StreamRedirectResolver(timeout: 2)
        let deadURL = URL(string: "http://127.0.0.1:1/unreachable.aac")!

        async let a = resolver.resolveFinalURL(for: deadURL)
        async let b = resolver.resolveFinalURL(for: deadURL)
        let results = await [a, b]
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0 == nil })
    }
}
