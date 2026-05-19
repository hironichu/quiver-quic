import NIOCore
import NIOUDPTransport
import QUICTransport
import QuiverRuntimeCore
import QuiverRuntimeTesting
import XCTest

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

final class RuntimeQUICSocketTests: XCTestCase {
    func testFactoryCreatesRuntimeSocketAndSendsThroughDatagramTransport() async throws {
        let runtime = CapturingRuntime()
        let udpConfiguration = UDPConfiguration(
            bindAddress: .specific(host: "127.0.0.1", port: 4433),
            streamBufferSize: 8
        )
        let socket = try QUICSocketFactory.makeSocket(
            backend: .runtime(runtime),
            udpConfiguration: udpConfiguration
        )

        try await socket.start()
        let maybeLocalAddress = await socket.localAddress
        let localAddress = try XCTUnwrap(maybeLocalAddress)
        XCTAssertEqual(localAddress.ipAddress, "127.0.0.1")
        XCTAssertEqual(localAddress.port, 4433)

        let remoteAddress = try SocketAddress(ipAddress: "127.0.0.1", port: 4444)
        try await socket.send(Data([1, 2, 3]), to: remoteAddress)

        let sent = runtime.transport.sentDatagrams
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].buffer.bytes, [1, 2, 3])
        XCTAssertEqual(sent[0].remoteAddress, RuntimeSocketAddress(ip: .v4(0x7f00_0001), port: 4444))

        await socket.stop()
    }
}

private struct CapturingRuntime: QuiverRuntime, Sendable {
    let clock: any RuntimeClock = ContinuousRuntimeClock()
    let reactor: any RuntimeReactor = InMemoryRuntimeReactor()
    let transport = CapturingDatagramTransport()

    func makeDatagramTransport(
        configuration: DatagramTransportConfiguration
    ) async throws -> any DatagramTransport {
        transport.configure(configuration)
        return transport
    }
}

private final class CapturingDatagramTransport: DatagramTransport, @unchecked Sendable {
    private struct State {
        var configuration: DatagramTransportConfiguration?
        var isRunning = false
        var localAddress: RuntimeSocketAddress?
        var sentDatagrams: [OutgoingDatagram] = []
    }

    private let lock = NSLock()
    private var state = State()
    let incomingDatagrams: AsyncStream<QuiverRuntimeCore.IncomingDatagram>

    init() {
        let stream = AsyncStream<QuiverRuntimeCore.IncomingDatagram> { continuation in
            continuation.finish()
        }
        self.incomingDatagrams = stream
    }

    var localAddress: RuntimeSocketAddress? {
        get async {
            lock.withLock { state.localAddress }
        }
    }

    var sentDatagrams: [OutgoingDatagram] {
        lock.withLock { state.sentDatagrams }
    }

    func configure(_ configuration: DatagramTransportConfiguration) {
        lock.withLock {
            state.configuration = configuration
        }
    }

    func start() async throws {
        lock.withLock {
            state.isRunning = true
            state.localAddress = state.configuration.map(Self.localAddress(for:))
        }
    }

    func stop() async {
        lock.withLock {
            state.isRunning = false
            state.localAddress = nil
        }
    }

    func send(_ datagram: OutgoingDatagram) async throws {
        lock.withLock {
            state.sentDatagrams.append(datagram)
        }
    }

    private static func localAddress(
        for configuration: DatagramTransportConfiguration
    ) -> RuntimeSocketAddress {
        switch configuration.bindAddress {
        case .any(let port), .ipv4Any(let port):
            return RuntimeSocketAddress(ip: .v4(0), port: port)
        case .ipv6Any(let port):
            return RuntimeSocketAddress(ip: .anyIPv6, port: port)
        case .specific(let address):
            return address
        }
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
