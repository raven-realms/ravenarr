import XCTest
@testable import Ravenarr

/// Locks in the exact regression reported in production: a completed
/// (approved + fully downloaded) request was mislabeled "Pending Approval"
/// because RequestApprovalStatus didn't model Overseerr's real 5-value
/// MediaRequestStatus enum (PENDING=1, APPROVED=2, DECLINED=3, FAILED=4,
/// COMPLETED=5) and silently fell back to .pending for anything unrecognized.
final class RequestApprovalStatusTests: XCTestCase {
    private func decodeRequest(status: Int) throws -> MediaRequest {
        let json = """
        { "id": 1, "status": \(status) }
        """
        return try JSONDecoder().decode(MediaRequest.self, from: Data(json.utf8))
    }

    func testPending() throws {
        XCTAssertEqual(try decodeRequest(status: 1).approvalStatus, .pending)
    }

    func testApproved() throws {
        XCTAssertEqual(try decodeRequest(status: 2).approvalStatus, .approved)
    }

    func testDeclined() throws {
        XCTAssertEqual(try decodeRequest(status: 3).approvalStatus, .declined)
    }

    func testFailed() throws {
        XCTAssertEqual(try decodeRequest(status: 4).approvalStatus, .failed)
    }

    /// The exact bug: this used to come back as .pending.
    func testCompletedIsNotPending() throws {
        let status = try decodeRequest(status: 5).approvalStatus
        XCTAssertEqual(status, .completed)
        XCTAssertNotEqual(status, .pending)
        XCTAssertEqual(status.label, "Completed")
    }
}
