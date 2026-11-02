import XCTest
import CryptoKit
@testable import LinguaMac

final class ModelDownloaderTests: XCTestCase {
    func testOrdinaryDownloadsWithoutHubCacheMetadataAndOfflineReuse() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-u", "-c", #"""
import http.server, json, hashlib, time
files = {'config.json': b'{}', 'tokenizer.json': b'{"version":"1.0"}', 'model.safetensors': b'x'*262144}
revision = 'a'*40
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        if self.headers.get('Authorization'):
            self.send_response(401); self.end_headers(); return
        if '/revision/main' in self.path: data=json.dumps({'sha':revision}).encode()
        elif '/tree/' in self.path:
            entries=[{'type':'file','path':k,'size':len(v),'lfs':{'oid':hashlib.sha256(v).hexdigest(),'size':len(v)}} for k,v in files.items()]
            data=json.dumps(entries).encode()
        elif '/resolve/' in self.path:
            name=self.path.split('/')[-1]
            if name not in files: self.send_response(404);self.end_headers();return
            data=files[name]
        else: self.send_response(404);self.end_headers();return
        self.send_response(200); self.send_header('Content-Length',str(len(data))); self.end_headers()
        # No ETag or X-Repo-Commit: ordinary responses must still land in real files.
        for i in range(0,len(data),8192):
            self.wfile.write(data[i:i+8192]); self.wfile.flush()
            if len(data)>65536: time.sleep(.02)
server=http.server.HTTPServer(('127.0.0.1',0),Handler)
print(server.server_port,flush=True);server.serve_forever()
"""#]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        let line = String(data: pipe.fileHandleForReading.availableData, encoding: .utf8)!
        let port = Int(line.trimmingCharacters(in: .whitespacesAndNewlines))!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let recorder = StatusRecorder()
        let downloader = ModelDownloader(endpoint: URL(string: "http://127.0.0.1:\(port)")!, root: folder)
        let snapshot = try await downloader.download(repository: "owner/model") { recorder.append($0) }
        XCTAssertEqual(try Data(contentsOf: snapshot.appendingPathComponent("tokenizer.json")), Data("{\"version\":\"1.0\"}".utf8))
        XCTAssertTrue(recorder.values.contains { $0.speed > 0 && $0.total == 262163 && $0.completed > 0 && $0.fraction < 1 })
        XCTAssertEqual(recorder.values.last?.phase, .loading)
        XCTAssertEqual(recorder.values.last?.fraction, 1)
        XCTAssertEqual(try downloader.cachedSnapshot(repository: "owner/model")?.path, snapshot.path)
        let resources = folder.appendingPathComponent("AppResources")
        let packagedRoot = resources.appendingPathComponent("BundledModels")
        try FileManager.default.createDirectory(at: packagedRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: snapshot.deletingLastPathComponent(), to: packagedRoot.appendingPathComponent("packaged"))
        let bundled = try XCTUnwrap(ModelDownloader.bundledSnapshot(repository: "owner/model", resources: resources, verifyContents: true))
        XCTAssertTrue(bundled.path.contains("AppResources/BundledModels/packaged"))
        XCTAssertNil(try ModelDownloader.bundledSnapshot(repository: "owner/other", resources: resources))
        XCTAssertNil(try ModelDownloader.bundledSnapshot(repository: "owner/model", resources: nil))
        // Cancelling a live transfer must terminate it and never publish a complete manifest.
        let cancelledRoot = folder.appendingPathComponent("cancelled")
        let cancelledDownloader = ModelDownloader(endpoint: URL(string: "http://127.0.0.1:\(port)")!, root: cancelledRoot)
        let pending = Task { try await cancelledDownloader.download(repository: "owner/model") { _ in } }
        try await Task.sleep(for: .milliseconds(200))
        pending.cancel()
        do { _ = try await pending.value; XCTFail("Cancelled download unexpectedly completed") }
        catch is CancellationError { }
        XCTAssertFalse((FileManager.default.enumerator(atPath: cancelledRoot.path)?.allObjects as? [String] ?? []).contains { $0.hasSuffix(".lingua-manifest.json") })
        process.terminate(); process.waitUntilExit()
        let reused = StatusRecorder()
        let cachedSnapshot = try await downloader.download(repository: "owner/model") { reused.append($0) }
        XCTAssertEqual(cachedSnapshot.path, snapshot.path)
        XCTAssertEqual(reused.values.last?.cached, 262163)
        let anotherSource = ModelDownloader(endpoint: URL(string: "http://127.0.0.1:1")!, root: folder)
        XCTAssertEqual(try anotherSource.cachedSnapshot(repository: "owner/model")?.resolvingSymlinksInPath().path, snapshot.resolvingSymlinksInPath().path)
        let offlineSnapshot = try await anotherSource.download(repository: "owner/model") { _ in }
        XCTAssertEqual(offlineSnapshot.resolvingSymlinksInPath().path, snapshot.resolvingSymlinksInPath().path)
        // Old manifests without repository metadata still resolve from their source-specific namespace.
        let manifestURL = snapshot.deletingLastPathComponent().appendingPathComponent(".lingua-manifest.json")
        var oldManifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        oldManifest.removeValue(forKey: "repository")
        try JSONSerialization.data(withJSONObject: oldManifest).write(to: manifestURL)
        XCTAssertEqual(try downloader.cachedSnapshot(repository: "owner/model")?.path, snapshot.path)
        XCTAssertNil(try anotherSource.cachedSnapshot(repository: "owner/another-model"))
        try Data("incomplete".utf8).write(to: snapshot.appendingPathComponent("model.safetensors"))
        XCTAssertNil(try downloader.cachedSnapshot(repository: "owner/model"))
    }
    func testUnsafePathsAndCorruptFilesAreRejected() throws {
        for path in ["../model.json", "/model.json", "a/../file", "a\\file", "a//file"] {
            XCTAssertThrowsError(try ModelDownloader.validatePath(path))
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("bad".utf8).write(to: file)
        let entry = ModelDownloader.Entry(type: "file", path: "model.safetensors", size: 3,
            lfs: .init(oid: SHA256.hash(data: Data("yes".utf8)).map { String(format: "%02x", $0) }.joined(), size: 3))
        XCTAssertFalse(try ModelDownloader.validFile(file, entry: entry))
    }
}
private final class StatusRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ModelDownloadStatus] = []
    var values: [ModelDownloadStatus] { lock.lock(); defer { lock.unlock() }; return items }
    func append(_ value: ModelDownloadStatus) { lock.lock(); items.append(value); lock.unlock() }
}
