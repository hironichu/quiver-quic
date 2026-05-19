import NIOCore
import NIOUDPTransport
import QUICCore
#if QUIVER_RUNTIME
import QuiverRuntimeCore
import Synchronization
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum QUICSocketBackend: Sendable {
    case nio
    #if QUIVER_RUNTIME
    case runtime(any QuiverRuntime)
    #endif
}

public enum QUICSocketFactory {
    public static func makeSocket(
        backend: QUICSocketBackend,
        udpConfiguration: UDPConfiguration,
        platformOptions: PlatformSocketOptions? = nil
    ) throws -> any QUICSocket {
        switch backend {
        case .nio:
            return NIOQUICSocket(configuration: udpConfiguration, platformOptions: platformOptions)
        #if QUIVER_RUNTIME
        case .runtime(let runtime):
            return try RuntimeQUICSocket(runtime: runtime, udpConfiguration: udpConfiguration)
        #endif
        }
    }
}

#if QUIVER_RUNTIME
public enum RuntimeQUICSocketError: Error, Equatable, Sendable {
    case unsupportedAddress(SocketAddress)
    case unsupportedRuntimeAddress(RuntimeSocketAddress)
    case invalidIPv4Address(String?)
    case invalidPort(Int?)
}

/// A QUIC socket backed by a Quiver runtime datagram transport.
///
/// This adapter lets QUIC choose the native Quiver runtime path while keeping
/// the same `QUICSocket` surface used by the existing NIO-backed socket.
public final class RuntimeQUICSocket: QUICSocket, Sendable {
    private let runtime: any QuiverRuntime
    private let configuration: DatagramTransportConfiguration
    private let incomingStream: AsyncStream<IncomingPacket>
    private let incomingContinuation: AsyncStream<IncomingPacket>.Continuation
    private let transportState = Mutex<TransportState>(TransportState())
    private let allocator = ByteBufferAllocator()

    private struct TransportState: Sendable {
        var transport: (any DatagramTransport)?
        var forwardingTask: Task<Void, Never>?
    }

    public var localAddress: SocketAddress? {
        get async {
            guard let transport = transportState.withLock({ $0.transport }) else {
                return nil
            }
            guard let runtimeAddress = await transport.localAddress else {
                return nil
            }
            return try? Self.socketAddress(from: runtimeAddress)
        }
    }

    public var incomingPackets: AsyncStream<IncomingPacket> {
        incomingStream
    }

    public init(
        runtime: any QuiverRuntime,
        configuration: DatagramTransportConfiguration
    ) {
        self.runtime = runtime
        self.configuration = configuration

        let streamAndContinuation = AsyncStream<IncomingPacket>.makeStream(
            bufferingPolicy: .bufferingNewest(configuration.receiveQueueLimit)
        )
        self.incomingStream = streamAndContinuation.stream
        self.incomingContinuation = streamAndContinuation.continuation
    }

    public convenience init(
        runtime: any QuiverRuntime,
        udpConfiguration: UDPConfiguration
    ) throws {
        try self.init(
            runtime: runtime,
            configuration: Self.runtimeConfiguration(from: udpConfiguration)
        )
    }

    public func start() async throws {
        let transport = try await runtime.makeDatagramTransport(configuration: configuration)
        try await transport.start()

        let continuation = incomingContinuation
        let allocator = allocator
        let task = Task {
            for await datagram in transport.incomingDatagrams {
                guard let remoteAddress = try? Self.socketAddress(from: datagram.remoteAddress) else {
                    continue
                }
                let packet = IncomingPacket(
                    buffer: allocator.buffer(bytes: datagram.buffer.bytes),
                    remoteAddress: remoteAddress,
                    receivedAt: datagram.receivedAt,
                    ecnCodepoint: Self.ecnCodepoint(from: datagram.ecn)
                )
                continuation.yield(packet)
            }
            continuation.finish()
        }

        let previous = transportState.withLock { state -> Task<Void, Never>? in
            let previous = state.forwardingTask
            state.transport = transport
            state.forwardingTask = task
            return previous
        }
        previous?.cancel()
    }

    public func stop() async {
        let state = transportState.withLock { state -> TransportState in
            let existing = state
            state.transport = nil
            state.forwardingTask = nil
            return existing
        }

        state.forwardingTask?.cancel()
        await state.transport?.stop()
        incomingContinuation.finish()
    }

    public func send(_ data: Data, to address: SocketAddress) async throws {
        guard let transport = transportState.withLock({ $0.transport }) else {
            throw RuntimeQUICSocketError.unsupportedAddress(address)
        }
        let runtimeAddress = try Self.runtimeAddress(from: address)
        try await transport.send(PacketBuffer(data), to: runtimeAddress)
    }

    public func sendBatch(_ packets: [Data], to address: SocketAddress) async throws {
        guard !packets.isEmpty else { return }
        guard let transport = transportState.withLock({ $0.transport }) else {
            throw RuntimeQUICSocketError.unsupportedAddress(address)
        }
        let runtimeAddress = try Self.runtimeAddress(from: address)
        let datagrams = packets.map { packet in
            OutgoingDatagram(buffer: PacketBuffer(packet), remoteAddress: runtimeAddress)
        }
        try await transport.sendBatch(datagrams)
    }

    private static func runtimeConfiguration(
        from configuration: UDPConfiguration
    ) throws -> DatagramTransportConfiguration {
        let bindAddress: DatagramTransportConfiguration.BindAddress
        switch configuration.bindAddress {
        case .any(let port):
            bindAddress = .any(port: UInt16(port))
        case .ipv4Any(let port):
            bindAddress = .ipv4Any(port: UInt16(port))
        case .ipv6Any(let port):
            bindAddress = .ipv6Any(port: UInt16(port))
        case .specific(let host, let port):
            let socketAddress = try SocketAddress(ipAddress: host, port: port)
            bindAddress = .specific(try runtimeAddress(from: socketAddress))
        }

        return DatagramTransportConfiguration(
            bindAddress: bindAddress,
            reuseAddress: configuration.reuseAddress,
            reusePort: configuration.reusePort,
            receiveBufferSize: configuration.receiveBufferSize,
            sendBufferSize: configuration.sendBufferSize,
            maxDatagramSize: configuration.maxDatagramSize,
            receiveQueueLimit: configuration.streamBufferSize,
            enableECN: configuration.enableECN
        )
    }

    private static func runtimeAddress(from address: SocketAddress) throws -> RuntimeSocketAddress {
        guard let port = address.port, UDPConfiguration.validPortRange.contains(port) else {
            throw RuntimeQUICSocketError.invalidPort(address.port)
        }
        guard let ipAddress = address.ipAddress,
              let ipv4 = parseIPv4(ipAddress) else {
            throw RuntimeQUICSocketError.invalidIPv4Address(address.ipAddress)
        }
        return RuntimeSocketAddress(ip: .v4(ipv4), port: UInt16(port))
    }

    private static func socketAddress(from address: RuntimeSocketAddress) throws -> SocketAddress {
        switch address.ip {
        case .v4(let ipv4):
            return try SocketAddress(ipAddress: formatIPv4(ipv4), port: Int(address.port))
        default:
            throw RuntimeQUICSocketError.unsupportedRuntimeAddress(address)
        }
    }

    private static func parseIPv4(_ string: String) -> UInt32? {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        var value: UInt32 = 0
        for part in parts {
            guard let byte = UInt8(part) else { return nil }
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    private static func formatIPv4(_ value: UInt32) -> String {
        let octet0 = UInt8(truncatingIfNeeded: value >> 24)
        let octet1 = UInt8(truncatingIfNeeded: value >> 16)
        let octet2 = UInt8(truncatingIfNeeded: value >> 8)
        let octet3 = UInt8(truncatingIfNeeded: value)
        return "\(octet0).\(octet1).\(octet2).\(octet3)"
    }

    private static func ecnCodepoint(from runtimeCodepoint: RuntimeECNCodepoint) -> ECNCodepoint {
        switch runtimeCodepoint {
        case .notECT:
            return .notECT
        case .ect0:
            return .ect0
        case .ect1:
            return .ect1
        case .ce:
            return .ce
        }
    }
}
#endif
