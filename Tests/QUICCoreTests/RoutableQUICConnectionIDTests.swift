import XCTest
@testable import QUICCore

final class RoutableQUICConnectionIDTests: XCTestCase {
    func testRoutableCIDEncodesBackendIDBigEndian() throws {
        let cid = try RoutableQUICConnectionID(
            backendID: 0x1234,
            randomBytes: [0, 1, 2, 3, 4, 5, 6, 7, 8]
        )

        XCTAssertEqual(cid.rawValue.count, 16)
        XCTAssertEqual(cid.rawValue[0], 0x01)
        XCTAssertEqual(cid.rawValue[1], 0x12)
        XCTAssertEqual(cid.rawValue[2], 0x34)
        XCTAssertEqual(cid.backendID, 0x1234)
    }

    func testRoutableCIDRejectsInvalidLength() {
        XCTAssertThrowsError(
            try RoutableQUICConnectionID(rawValue: [0x01, 0x00, 0x01])
        )
    }

    func testRoutableCIDRejectsInvalidFormatVersion() {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 0x02

        XCTAssertThrowsError(
            try RoutableQUICConnectionID(rawValue: bytes)
        )
    }

    func testGeneratorProducesExpectedBackendID() throws {
        let generator = RoutableQUICConnectionIDGenerator(backendID: 42)
        let cid = try generator.generateConnectionID()
        let bytes = Array(cid.bytes)

        XCTAssertEqual(cid.length, 16)
        XCTAssertEqual(bytes[0], 0x01)
        XCTAssertEqual(bytes[1], 0x00)
        XCTAssertEqual(bytes[2], 0x2a)
    }
}
