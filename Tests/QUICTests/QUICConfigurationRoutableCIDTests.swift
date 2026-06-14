import XCTest
@testable import QUIC
@testable import QUICCore

final class QUICConfigurationRoutableCIDTests: XCTestCase {
    func testMakeLocalConnectionIDUsesConfiguredBackendID() throws {
        var config = QUICConfiguration()
        config.connectionIDLength = 16
        config.routableConnectionIDBackendID = 9

        let cid = try config.makeLocalConnectionID()
        let bytes = Array(cid.bytes)

        XCTAssertEqual(cid.length, 16)
        XCTAssertEqual(bytes[0], 0x01)
        XCTAssertEqual(bytes[1], 0x00)
        XCTAssertEqual(bytes[2], 0x09)
    }

    func testDefaultMakeLocalConnectionIDUsesConfiguredLength() throws {
        var config = QUICConfiguration()
        config.connectionIDLength = 8
        config.routableConnectionIDBackendID = nil

        let cid = try config.makeLocalConnectionID()

        XCTAssertEqual(cid.length, 8)
    }
}
