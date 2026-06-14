public typealias QUICConnectionIDGenerator = @Sendable (_ requestedLength: Int) throws -> ConnectionID

public enum QUICConnectionIDGeneratorError: Error, Sendable, Equatable {
    case invalidLength(Int)
}

public enum QUICConnectionIDGenerators {
    public static let random: QUICConnectionIDGenerator = { requestedLength in
        guard let cid = ConnectionID.random(length: requestedLength) else {
            throw QUICConnectionIDGeneratorError.invalidLength(requestedLength)
        }

        return cid
    }
}
