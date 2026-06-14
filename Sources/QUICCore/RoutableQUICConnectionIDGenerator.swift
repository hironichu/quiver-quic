public struct RoutableQUICConnectionIDGenerator: Sendable {
    public let backendID: UInt16

    public init(backendID: UInt16) {
        self.backendID = backendID
    }

    public func generateBytes() throws -> [UInt8] {
        try RoutableQUICConnectionID(
            backendID: backendID,
            randomBytes: Self.randomBytes(count: 9)
        ).rawValue
    }

    public func generateConnectionID() throws -> ConnectionID {
        try ConnectionID(generateBytes())
    }

    public var asQUICConnectionIDGenerator: QUICConnectionIDGenerator {
        { _ in
            try generateConnectionID()
        }
    }

    private static func randomBytes(count: Int) -> [UInt8] {
        var rng = SystemRandomNumberGenerator()
        return (0..<count).map { _ in
            UInt8.random(in: UInt8.min...UInt8.max, using: &rng)
        }
    }
}
