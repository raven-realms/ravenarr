import XCTest
@testable import Ravenarr

/// Permission bitmask: ADMIN = 2, MANAGE_REQUESTS = 16, MANAGE_ISSUES = 8192.
final class SeerrUserPermissionsTests: XCTestCase {
    private func makeUser(permissions: Int?) -> SeerrUser {
        let json: String
        if let permissions {
            json = "{ \"id\": 1, \"permissions\": \(permissions) }"
        } else {
            json = "{ \"id\": 1 }"
        }
        return try! JSONDecoder().decode(SeerrUser.self, from: Data(json.utf8))
    }

    func testAdminBitGrantsManage() {
        let user = makeUser(permissions: 2)
        XCTAssertTrue(user.isAdmin)
        XCTAssertTrue(user.canManage)
    }

    func testManageRequestsAloneIsNotAdminButCanManage() {
        let user = makeUser(permissions: 16)
        XCTAssertFalse(user.isAdmin)
        XCTAssertTrue(user.canManage)
    }

    func testManageIssuesAloneIsNotAdminButCanManage() {
        let user = makeUser(permissions: 8192)
        XCTAssertFalse(user.isAdmin)
        XCTAssertTrue(user.canManage)
    }

    func testNoPermissionsCannotManage() {
        let user = makeUser(permissions: 0)
        XCTAssertFalse(user.isAdmin)
        XCTAssertFalse(user.canManage)
    }

    func testMissingPermissionsFieldCannotManage() {
        let user = makeUser(permissions: nil)
        XCTAssertFalse(user.isAdmin)
        XCTAssertFalse(user.canManage)
    }

    func testCombinedBitsStillWork() {
        // ADMIN (2) + MANAGE_REQUESTS (16) + MANAGE_ISSUES (8192) = 8210
        let user = makeUser(permissions: 8210)
        XCTAssertTrue(user.isAdmin)
        XCTAssertTrue(user.canManage)
    }
}
