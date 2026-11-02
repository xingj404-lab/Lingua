import XCTest
@testable import LinguaMac

final class APICredentialsTests: XCTestCase {
    private func fixture(_ operation: (APICredentialStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try operation(APICredentialStore(directory: directory), directory)
    }

    func testKeysPersistAcrossStoreInstancesAndUsePrivatePermissions() throws {
        try fixture { store, directory in
            let endpoint = URL(string: "https://example.invalid/v1")!
            XCTAssertNil(try store.read(endpoint: endpoint))
            try store.save("fixture-key", endpoint: endpoint)
            let reopened = APICredentialStore(directory: directory)
            XCTAssertEqual(try reopened.read(endpoint: endpoint), "fixture-key")
            try store.save("updated-key", endpoint: endpoint)
            XCTAssertEqual(try reopened.read(endpoint: endpoint), "updated-key")
            for (url, mode) in [(directory, 0o700), (directory.appendingPathComponent("api-keys.json"), 0o600)] {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, mode)
            }
        }
    }

    func testNormalizedEndpointsShareKeysButDifferentServicesRemainIsolated() throws {
        try fixture { store, _ in
            let first = URL(string: "https://EXAMPLE.invalid:443/v1/")!
            let equivalent = URL(string: "https://example.invalid/v1")!
            let second = URL(string: "https://other.invalid/v1")!
            let otherPath = URL(string: "https://example.invalid/v2")!
            try store.save("first", endpoint: first)
            try store.save("second", endpoint: second)
            XCTAssertEqual(try store.read(endpoint: equivalent), "first")
            XCTAssertEqual(try store.read(endpoint: second), "second")
            XCTAssertNil(try store.read(endpoint: otherPath))
            try store.save("", endpoint: equivalent)
            XCTAssertNil(try store.read(endpoint: first))
            XCTAssertEqual(try store.read(endpoint: second), "second")
        }
    }

    func testRemovingLastKeyDeletesCredentialFileAndMissingRemovalDoesNothing() throws {
        try fixture { store, directory in
            let endpoint = URL(string: "https://example.invalid/v1")!
            try store.save("", endpoint: endpoint)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
            try store.save("fixture", endpoint: endpoint)
            try store.save("", endpoint: endpoint)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("api-keys.json").path))
            XCTAssertNil(try store.read(endpoint: endpoint))
        }
    }

    func testCorruptFileIsReportedAndPreserved() throws {
        try fixture { store, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("api-keys.json")
            let original = Data("invalid-json".utf8)
            try original.write(to: file)
            let endpoint = URL(string: "https://example.invalid/v1")!
            XCTAssertThrowsError(try store.read(endpoint: endpoint))
            XCTAssertThrowsError(try store.save("replacement", endpoint: endpoint))
            XCTAssertEqual(try Data(contentsOf: file), original)
        }
    }

    func testConcurrentSavesDoNotLoseOtherEndpointKeys() throws {
        try fixture { store, _ in
            DispatchQueue.concurrentPerform(iterations: 32) { index in
                do { try store.save("fixture-\(index)", endpoint: URL(string: "https://example.invalid/\(index)")!) }
                catch { XCTFail("Local save failed: \(error)") }
            }
            for index in 0..<32 {
                XCTAssertEqual(try store.read(endpoint: URL(string: "https://example.invalid/\(index)")!), "fixture-\(index)")
            }
        }
    }
}
