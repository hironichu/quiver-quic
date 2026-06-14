import XCTest
@testable import QUICCore
@testable import QUICConnection

final class ConnectionIDManagerCIDGeneratorTests: XCTestCase {
    func testIssueNewConnectionIDUsesInjectedGenerator() throws {
        let manager = ConnectionIDManager(
            activeConnectionIDLimit: 4,
            connectionIDGenerator: RoutableQUICConnectionIDGenerator(
                backendID: 7
            ).asQUICConnectionIDGenerator
        )

        let frame = try manager.issueNewConnectionID(length: 16)
        let bytes = Array(frame.connectionID.bytes)

        XCTAssertEqual(frame.connectionID.length, 16)
        XCTAssertEqual(bytes[0], 0x01)
        XCTAssertEqual(bytes[1], 0x00)
        XCTAssertEqual(bytes[2], 0x07)
    }
}
