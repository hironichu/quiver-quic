# quiver-quic

QUIC protocol implementation for Quiver. This package contains the transport, TLS 1.3 integration, stream management, recovery, packet processing, and low-level UDP transport layers used by the higher-level Quiver packages.

## Products

| Product | Purpose |
| --- | --- |
| `QUIC` | High-level client/server endpoint API, managed connections, streams, packet routing, and configuration. |
| `QUICCore` | Core protocol types such as packets, frames, varints, connection IDs, transport parameters, and QUIC errors. |
| `QUICCrypto` | QUIC TLS 1.3 integration, AEAD, header protection, X.509 validation, session tickets, and key derivation. |
| `QUICStream` | Stream state machines, flow control, priority scheduling, stream identifiers, and buffering. |
| `QUICRecovery` | ACK management, RTT estimation, loss detection, congestion control, pacing support, and packet number spaces. |
| `QUICTransport` | UDP socket integration and platform transport helpers. |
| `NIOUDPTransport` | NIO-based UDP transport primitives used by QUIC transport code. |
| `QUICConnection` | Lower-level connection state machine components used by the public `QUIC` target. |
| `QuiverTestSupport` | Shared test support utilities for Quiver package tests. |

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
	.package(url: "https://github.com/hironichu/quiver-quic.git", branch: "main")
]
```

Then depend on the products you need:

```swift
.target(
	name: "MyTarget",
	dependencies: [
		.product(name: "QUIC", package: "quiver-quic"),
		.product(name: "QUICCore", package: "quiver-quic"),
		.product(name: "QUICCrypto", package: "quiver-quic"),
	]
)
```

## Local Development

This repository is designed to sit next to the other Quiver packages under a shared checkout directory:

```text
quiver-packages/
├── quiver-quic/
├── quiver-http3/
├── quiver-webtransport/
├── quiver-auth/
├── quiver-adapters/
└── quiver-moq/
```

For Swift CI style local dependency testing, set `SWIFTCI_USE_LOCAL_DEPS=1` and place local `swift-nio`, `swift-nio-ssl`, and `swift-system` checkouts next to this package or one directory above the package group, depending on your workspace layout.

## Development Commands

```bash
swift build
swift test
```

## Relationship To Quiver

The root `quiver` package aggregates this package through SwiftPM package traits. Use this package directly when you only need the QUIC layers or want to develop the protocol stack independently.
