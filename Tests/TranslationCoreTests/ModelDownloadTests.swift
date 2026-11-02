import XCTest
@testable import TranslationCore

final class ModelDownloadTests: XCTestCase {
    func testMirrorLinksUseTheSelectedHost() throws {
        let mirror = try ModelDownloadSource.mirror.endpoint()
        let files = try ModelDownloads.repositoryURL(endpoint: mirror, repository: "mlx-community/Qwen3-4B-4bit", files: true)
        XCTAssertEqual(files.absoluteString, "https://hf-mirror.com/mlx-community/Qwen3-4B-4bit/tree/main")
        let custom = try ModelDownloadSource.custom.endpoint(custom: "https://models.example.com/")
        XCTAssertEqual(try ModelDownloads.repositoryURL(endpoint: custom, repository: "owner/model").host, "models.example.com")
        XCTAssertEqual(try ModelDownloadSource.official.endpoint().host, "huggingface.co")
    }
    func testDownloadSourceAndRepositoryValidation() throws {
        for source in ["http://hf-mirror.com", "https://user:secret@hf-mirror.com", "https://hf-mirror.com/model", "https://hf-mirror.com?token=test", "https://hf-mirror.com/#test"] {
            XCTAssertThrowsError(try ModelDownloads.validateEndpoint(source), source)
        }
        for repository in ["../model", "https://example.com/model", "owner/model/resolve", "owner/model?token=test", "owner/model\nextra"] {
            XCTAssertThrowsError(try ModelDownloads.validateRepository(repository), repository)
        }
        XCTAssertEqual(try ModelDownloads.validateRepository(" owner/model "), "owner/model")
    }
}
