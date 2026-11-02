import XCTest
@testable import LinguaMac

final class APIConsentTests: XCTestCase {
    @MainActor
    private func fixture(_ operation: (Workspace) -> Void) {
        let defaults = UserDefaults.standard
        let keys = ["endpoint", "backend", "serverModel", "consentedAPIEndpoints.v1"]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.removeObject(forKey: "consentedAPIEndpoints.v1")
        let workspace = Workspace()
        workspace.backend = .server
        workspace.endpoint = "https://consent-test.invalid/\(UUID().uuidString)/v1"
        workspace.serverModel = "test-model"
        workspace.source = "Keep this source"
        workspace.output = "Keep this translation"
        workspace.apiKeyLoading = false
        operation(workspace)
    }

    @MainActor
    func testUnapprovedAPIRequestRequiresConsentWithoutClearingTextOrSending() {
        fixture { workspace in
            workspace.translate()
            XCTAssertEqual(workspace.pendingAPIConsentEndpoint, workspace.endpoint)
            XCTAssertFalse(workspace.busy, "No network task may start before consent")
            XCTAssertEqual(workspace.source, "Keep this source")
            XCTAssertEqual(workspace.output, "Keep this translation")
            let previous = workspace.endpoint
            workspace.endpoint = "https://different-service.invalid/v1"
            XCTAssertNil(workspace.pendingAPIConsentEndpoint, "Changing service dismisses the stale inline prompt")
            workspace.approveAPIConsent(previous)
            XCTAssertFalse(workspace.busy, "A consent response for a previous address cannot authorize a new one")
            XCTAssertNil(UserDefaults.standard.stringArray(forKey: "consentedAPIEndpoints.v1"))
        }
    }

    @MainActor
    func testCancellingInlineConsentPreservesTextAndDoesNotAuthorizeSending() {
        fixture { workspace in
            workspace.translate()
            let address = workspace.endpoint
            workspace.pendingAPIConsentEndpoint = nil
            workspace.approveAPIConsent(address)
            XCTAssertFalse(workspace.busy)
            XCTAssertEqual(workspace.source, "Keep this source")
            XCTAssertEqual(workspace.output, "Keep this translation")
            XCTAssertNil(UserDefaults.standard.stringArray(forKey: "consentedAPIEndpoints.v1"))
            workspace.translate()
            XCTAssertEqual(workspace.pendingAPIConsentEndpoint, address)
        }
    }

    @MainActor
    func testSwitchingBackendOrResettingDismissesInlineConsent() {
        fixture { workspace in
            workspace.translate()
            let address = workspace.endpoint
            workspace.backend = .native
            XCTAssertNil(workspace.pendingAPIConsentEndpoint)
            workspace.approveAPIConsent(address)
            XCTAssertFalse(workspace.busy)
            XCTAssertNil(UserDefaults.standard.stringArray(forKey: "consentedAPIEndpoints.v1"))
            workspace.backend = .server
            workspace.translate()
            XCTAssertEqual(workspace.pendingAPIConsentEndpoint, address)
            workspace.reset()
            XCTAssertNil(workspace.pendingAPIConsentEndpoint)
        }
    }

    @MainActor
    func testRevokingSavedConsentRequiresInlineConfirmationAgain() {
        fixture { workspace in
            UserDefaults.standard.set([workspace.endpoint], forKey: "consentedAPIEndpoints.v1")
            workspace.revokeAPIConsent()
            workspace.translate()
            XCTAssertEqual(workspace.pendingAPIConsentEndpoint, workspace.endpoint)
            XCTAssertFalse(workspace.busy)
        }
    }
}
