import XCTest
@testable import LinguaMac
import TranslationCore

final class LocalServerTests: XCTestCase {
    func testRemoteRequestURLAndAuthentication() throws {
        let request = TranslationRequest(text: "Hello", options: .init(), glossary: [])
        let engine = APIServiceEngine(endpoint: "https://llm.example.com/v1/", model: "remote-model", apiKey: "test-key")
        let http = try engine.makeURLRequest(request)
        XCTAssertEqual(http.url?.absoluteString, "https://llm.example.com/v1/chat/completions")
        XCTAssertEqual(http.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(http.httpMethod, "POST")
        let anonymous = try APIServiceEngine(endpoint: "http://localhost:8080/v1", model: "test").makeURLRequest(request)
        XCTAssertNil(anonymous.value(forHTTPHeaderField: "Authorization"))
        XCTAssertThrowsError(try APIServiceEngine(endpoint: "https://example.com/v1", model: " ").makeURLRequest(request))
        XCTAssertThrowsError(try APIServiceEngine(endpoint: "https://example.com/v1", model: "test", apiKey: "key\nheader").makeURLRequest(request))
    }
    func testLocalHTTPContractTruncationAndRedirects() async throws {
        // A loopback fixture exercises real URLSession behavior, including redirect refusal.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-u", "-c", #"""
import http.server, json
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        if self.path.startswith('/redirect/'):
            self.send_response(302)
            self.send_header('Location', 'https://example.com/cloud')
            self.end_headers()
            return
        payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        valid = self.headers.get('Authorization') == 'Bearer fixture-token' and self.headers.get('Content-Type') == 'application/json' and payload['model'] == 'fixture-model' and payload['stream'] == False and payload['messages'][0]['role'] == 'system'
        valid = valid and '统一内存' in payload['messages'][0]['content'] and '512' in payload['messages'][1]['content']
        if not valid:
            self.send_response(422); self.end_headers(); return
        response = {'choices': [{'message': {'role': 'assistant', 'content': '统一内存需要 512 MB。'}, 'finish_reason': 'length' if self.path.startswith('/length/') else 'stop'}]}
        body = json.dumps(response).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers(); self.wfile.write(body)
server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
"""#]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        let announcement = pipe.fileHandleForReading.availableData
        guard let value = String(data: announcement, encoding: .utf8), let port = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw XCTSkip("Python 3 loopback fixture could not start")
        }
        let request = TranslationRequest(text: "Unified memory needs 512 MB.", options: .init(domain: .technical),
            glossary: [.init(source: "unified memory", target: "统一内存")])
        let result = try await APIServiceEngine(endpoint: "http://127.0.0.1:\(port)/v1", model: "fixture-model", apiKey: "fixture-token").translate(request)
        XCTAssertEqual(result, "统一内存需要 512 MB。")
        do {
            _ = try await APIServiceEngine(endpoint: "http://127.0.0.1:\(port)/length", model: "fixture-model", apiKey: "fixture-token").translate(request)
            XCTFail("Truncated results must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("长度上限")) }
        do {
            _ = try await APIServiceEngine(endpoint: "http://127.0.0.1:\(port)/redirect", model: "fixture-model", apiKey: "fixture-token").translate(request)
            XCTFail("Redirects must fail without reaching a remote host")
        } catch { XCTAssertTrue(error.localizedDescription.contains("302")) }
    }
}
