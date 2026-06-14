
public struct RoutableQUICConnectionID: Sendable, Hashable {
    public static let length = 16
    public static let formatVersion: UInt8 = 0x01

    public let rawValue: [UInt8]

    public init(rawValue: [UInt8]) throws {
        guard rawValue.count == Self.length else {
            throw RoutableQUICConnectionIDError.invalidLength
        }

        guard rawValue[0] == Self.formatVersion else {
            throw RoutableQUICConnectionIDError.invalidFormat
        }

        self.rawValue = rawValue
    }

    public init(
        backendID: UInt16,
        randomBytes: [UInt8]
    ) throws {
        guard randomBytes.count == 9 else {
            throw RoutableQUICConnectionIDError.invalidRandomLength
        }

        var cid = [UInt8](repeating: 0, count: Self.length)

        cid[0] = Self.formatVersion
        cid[1] = UInt8(backendID >> 8)
        cid[2] = UInt8(backendID & 0xff)
        cid[3..<12] = randomBytes[0..<9]

        // Temporary marker. Replace with MAC later.
        cid[12] = 0xaa
        cid[13] = 0xbb
        cid[14] = 0xcc
        cid[15] = 0xdd

        self.rawValue = cid
    }

    public var backendID: UInt16 {
        (UInt16(rawValue[1]) << 8) | UInt16(rawValue[2])
    }
}

public enum RoutableQUICConnectionIDError: Error, Sendable {
    case invalidLength
    case invalidFormat
    case invalidRandomLength
}
