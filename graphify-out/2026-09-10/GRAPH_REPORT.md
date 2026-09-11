# Graph Report - AirCatch  (2026-09-10)

## Corpus Check
- 36 files · ~51,818 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1089 nodes · 2120 edges · 158 communities (42 shown, 116 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 66 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `26659972`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- HostManager
- NetworkManager
- Foundation
- Bool
- ScreenStreamer
- NetworkManager
- Bool
- VirtualDisplayManager
- MouseHandlingView
- View
- MetalVideoRenderer
- Bool
- Bool
- AirCatchClientApp
- AirCatchClient/SharedModels.swift
- InputInjector
- ClientManager
- MPCAirCatchClient
- NetworkHealthMonitor
- MPCAirCatchHost
- ExtendedDisplayPosition
- String
- VideoDecoder
- Int
- HostView
- PacketType
- Bool
- RTCPeerConnectionState
- DisplayManager
- CryptoManager
- AirCatchHost/SharedModels.swift
- ScreenStreamer.swift
- AudioPlayer
- CryptoManager
- Codable
- ExtendedDisplayPosition
- UDPStreamProcessor
- AppKit
- ExtendedDisplayResolution
- .handleTCPPacket
- Int
- CFTimeInterval
- iPadDisplayPreset
- BonjourBrowser
- TouchEventType
- TouchEventType
- Float
- ConnectionState
- .setStreamingStateIfNeeded
- ConnectionOption
- manifest.json
- launch_retry.sh
- RelayClient
- WebRTCSignalMessage
- CFTimeInterval
- KeyModifiers
- RTCVideoTrack
- Timer
- Context
- Data
- CGSize
- Error
- PacketType
- SecTrust
- Set
- String
- ObjectIdentifier
- URL
- URLAuthenticationChallenge
- URLCredential
- URLSession
- URLSessionTask
- URLSessionWebSocketTask
- Void
- Data
- RTCDataBuffer
- RTCDataChannel
- RTCIceCandidate
- RTCIceConnectionState
- RTCIceGatheringState
- RTCIceServer
- RTCMediaStream
- RTCPeerConnection
- RTCPeerConnectionFactory
- RTCPeerConnectionState
- RTCSignalingState
- RTCVideoTrack
- Void
- WebRTCIceServerConfig
- WebRTCSignalMessage
- Context
- RTCVideoTrack
- MCPeerID
- PacketType
- RelayClient
- RTCPeerConnectionState
- WebRTCSignalMessage
- NWListener
- Data
- Error
- PacketType
- SecTrust
- Set
- String
- TimeInterval
- URL
- URLAuthenticationChallenge
- URLCredential
- URLSession
- URLSessionTask
- URLSessionWebSocketTask
- Void
- Date
- DispatchQueue
- OSStatus
- CMTime
- CVPixelBuffer
- Data
- Double
- Int
- Int64
- RTCDataBuffer
- RTCDataChannel
- RTCIceCandidate
- RTCIceConnectionState
- RTCIceGatheringState
- RTCIceServer
- RTCMediaStream
- RTCPeerConnection
- RTCPeerConnectionFactory
- RTCPeerConnectionState
- RTCSignalingState
- RTCVideoTrack
- Void
- WebRTCIceServerConfig
- WebRTCSignalMessage
- CGDirectDisplayID
- CGPoint
- CMTime
- CVPixelBuffer
- Int32
- NWConnection
- NWEndpoint
- RTCDataChannelDelegate
- RTCDegradationPreference
- RTCMTLVideoView
- RTCPeerConnectionDelegate
- RTCRtpReceiver
- RTCRtpSender
- RTCVideoCapturer
- RTCVideoSource
- RTCVideoTrack
- ScreenStreamer
- TouchEventType
- UInt16
- URLSessionWebSocketDelegate
- WebRTCClientSession
- WebRTCHostSession

## God Nodes (most connected - your core abstractions)
1. `ClientManager` - 66 edges
2. `HostManager` - 64 edges
3. `ScreenStreamer` - 39 edges
4. `NetworkManager` - 32 edges
5. `MetalVideoRenderer` - 28 edges
6. `VirtualDisplayManager` - 27 edges
7. `MouseHandlingView` - 24 edges
8. `VideoStreamViewModel` - 22 edges
9. `MPCAirCatchHost` - 22 edges
10. `NetworkManager` - 21 edges

## Surprising Connections (you probably didn't know these)
- `DiscoveredHost` --references--> `Network`  [EXTRACTED]
  AirCatchClient/SharedModels.swift → AirCatchHost/SharedModels.swift
- `.body` --calls--> `ContentView`  [INFERRED]
  AirCatchClient/AirCatchClientApp.swift → AirCatchClient/ContentView.swift
- `.localModeSection` --references--> `HostManager`  [INFERRED]
  AirCatchHost/HostView.swift → AirCatchHost/HostManager.swift
- `.body` --calls--> `HostView`  [INFERRED]
  AirCatchHost/AirCatchHostApp.swift → AirCatchHost/HostView.swift
- `ClientManager` --calls--> `BonjourBrowser`  [INFERRED]
  AirCatchClient/ClientManager.swift → AirCatchClient/BonjourBrowser.swift

## Import Cycles
- None detected.

## Communities (158 total, 116 thin omitted)

### Community 0 - "HostManager"
Cohesion: 0.08
Nodes (23): BonjourAdvertiser, NWListener, String, UInt16, CachedFrame, HostManager, .statusDescription, InputStateCache (+15 more)

### Community 1 - "NetworkManager"
Cohesion: 0.18
Nodes (10): NetworkManager, Data, NWConnection, NWEndpoint, Packet, PacketType, String, UInt16 (+2 more)

### Community 2 - "Foundation"
Cohesion: 0.19
Nodes (6): Combine, CommonCrypto, Foundation, MultipeerConnectivity, Network, Security

### Community 4 - "ScreenStreamer"
Cohesion: 0.09
Nodes (26): ScreenStreamer, StreamerError, compressionSessionCreationFailed, noDisplayFound, StreamOutput, Bool, CGDirectDisplayID, CMTime (+18 more)

### Community 5 - "NetworkManager"
Cohesion: 0.16
Nodes (13): NetworkManager, Bool, Data, MainActor, NWConnection, NWEndpoint, Packet, PacketType (+5 more)

### Community 7 - "VirtualDisplayManager"
Cohesion: 0.11
Nodes (26): CGVirtualDisplay, CGVirtualDisplayDescriptor, CGVirtualDisplayMode, CGVirtualDisplaySettings, AnyObject, Bool, CGDirectDisplayID, CGPoint (+18 more)

### Community 8 - "MouseHandlingView"
Cohesion: 0.10
Nodes (21): MouseHandlingView, MouseInputView, Bool, CGPoint, CGRect, Int, Set, TouchEventType (+13 more)

### Community 9 - "View"
Cohesion: 0.10
Nodes (34): AboutScreen, .body, ContentView, .body, DevicesBackground, .body, DevicesScreen, .body (+26 more)

### Community 10 - "MetalVideoRenderer"
Cohesion: 0.07
Nodes (34): MetalVideoRenderer, MetalVideoView, CGSize, Context, CVPixelBuffer, Float, Int, ObjectIdentifier (+26 more)

### Community 13 - "AirCatchClientApp"
Cohesion: 0.17
Nodes (10): AirCatchClientApp, .body, Scene, AirCatchHostApp, .body, HostAppDelegate, Scene, App (+2 more)

### Community 14 - "AirCatchClient/SharedModels.swift"
Cohesion: 0.07
Nodes (45): AirCatchConfig, AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode (+37 more)

### Community 15 - "InputInjector"
Cohesion: 0.14
Nodes (13): InputInjector, .hasAccessibilityPermission, Bool, CGPoint, CGRect, Double, Int32, Int64 (+5 more)

### Community 16 - "ClientManager"
Cohesion: 0.11
Nodes (13): ClientManager, .savedSessionToken, Double, Int32, PacketType, String, TouchEventType, ConnectionMode (+5 more)

### Community 17 - "MPCAirCatchClient"
Cohesion: 0.13
Nodes (17): MPCAirCatchClient, Data, Error, InputStream, MCPeerID, MCSession, MCSessionSendDataMode, MCSessionState (+9 more)

### Community 18 - "NetworkHealthMonitor"
Cohesion: 0.10
Nodes (18): BitrateCalculator, Double, Int, String, NetworkHealthMonitor, SignalQuality, excellent, fair (+10 more)

### Community 19 - "MPCAirCatchHost"
Cohesion: 0.15
Nodes (18): MPCAirCatchHost, .hasConnectedPeers, Bool, Data, Error, InputStream, MCPeerID, MCSession (+10 more)

### Community 20 - "ExtendedDisplayPosition"
Cohesion: 0.11
Nodes (20): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, ExtendedDisplayResolution (+12 more)

### Community 21 - "String"
Cohesion: 0.18
Nodes (13): AirCatchLog, Category, general, input, network, video, AirCatchLog, Category (+5 more)

### Community 22 - "VideoDecoder"
Cohesion: 0.11
Nodes (19): Bool, CMTime, CVPixelBuffer, Data, Int, OSStatus, UInt8, VideoDecoder (+11 more)

### Community 23 - "Int"
Cohesion: 0.16
Nodes (18): AuthChallenge, AuthResponse, CodecPreference, auto, h264, hevc, ConnectionMode, localNetwork (+10 more)

### Community 24 - "HostView"
Cohesion: 0.25
Nodes (8): HostView, .body, .connectionStatusSection, .localModeSection, .statusColor, .statusDescription, Color, String

### Community 25 - "PacketType"
Cohesion: 0.05
Nodes (37): PacketType, audioPCM, authChallenge, authResponse, disconnect, handshake, handshakeAck, keyEvent (+29 more)

### Community 26 - "Bool"
Cohesion: 0.25
Nodes (4): AtomicBool, .audioEnabled, Bool, DiscoveredHost

### Community 28 - "DisplayManager"
Cohesion: 0.32
Nodes (4): DisplayManager, Double, Int, CGDisplayMode

### Community 29 - "CryptoManager"
Cohesion: 0.23
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 30 - "AirCatchHost/SharedModels.swift"
Cohesion: 0.19
Nodes (15): AirCatchConfig, DiscoveredHost, MediaKeyEvent, PingPacket, PongPacket, QualityReport, ScrollEvent, Double (+7 more)

### Community 31 - "ScreenStreamer.swift"
Cohesion: 0.16
Nodes (9): Accelerate, AVFoundation, CoreMedia, CoreVideo, IOSurface, MetalKit, ScreenCaptureKit, SwiftUI (+1 more)

### Community 32 - "AudioPlayer"
Cohesion: 0.22
Nodes (6): AudioPlayer, Data, Double, Int, UInt32, AVAudioFormat

### Community 33 - "CryptoManager"
Cohesion: 0.24
Nodes (8): CryptoManager, .isReady, Bool, Data, Int, String, SymmetricKey, UInt32

### Community 34 - "Codable"
Cohesion: 0.44
Nodes (7): KeyEvent, KeyModifiers, KeyEvent, KeyModifiers, Codable, OptionSet, Sendable

### Community 35 - "ExtendedDisplayPosition"
Cohesion: 0.18
Nodes (13): ExtendedDisplayConfig, ExtendedDisplayPosition, above, below, .displayName, left, right, StreamDisplayMode (+5 more)

### Community 36 - "UDPStreamProcessor"
Cohesion: 0.25
Nodes (13): ChunkSlice, FrameAssembly, Data, Set, TimeInterval, UInt16, UInt32, Void (+5 more)

### Community 37 - "AppKit"
Cohesion: 0.50
Nodes (3): AppKit, CoreGraphics, IOKit.hidsystem

### Community 38 - "ExtendedDisplayResolution"
Cohesion: 0.33
Nodes (6): ExtendedDisplayResolution, .displayName, matched, native, retina, standard

### Community 39 - ".handleTCPPacket"
Cohesion: 0.32
Nodes (4): error, Packet, UncheckedSendable, T

### Community 40 - "Int"
Cohesion: 0.25
Nodes (3): AtomicInt, Int, VideoChunkNackRequest

### Community 42 - "iPadDisplayPreset"
Cohesion: 0.17
Nodes (11): iPadDisplayPreset, .aspectRatio, .displayName, generic, iPadAir109, iPadMini6, iPadPro11, iPadPro129 (+3 more)

### Community 43 - "BonjourBrowser"
Cohesion: 0.25
Nodes (7): BonjourBrowser, DiscoveredHost, MainActor, String, UInt16, Void, NWBrowser

### Community 44 - "TouchEventType"
Cohesion: 0.20
Nodes (10): TouchEventType, began, cancelled, doubleClick, dragBegan, dragEnded, dragMoved, ended (+2 more)

### Community 45 - "TouchEventType"
Cohesion: 0.20
Nodes (10): TouchEventType, began, cancelled, doubleClick, dragBegan, dragEnded, dragMoved, ended (+2 more)

### Community 47 - "ConnectionState"
Cohesion: 0.25
Nodes (8): ConnectionState, connected, connecting, disconnected, discovering, .displayDescription, .isConnected, streaming

### Community 49 - "ConnectionOption"
Cohesion: 0.29
Nodes (7): ConnectionOption, .displayName, .id, .includePeerToPeer, udpNetworkFramework, udpPeerToPeerAWDL, Identifiable

## Knowledge Gaps
- **176 isolated node(s):** `disconnected`, `discovering`, `connecting`, `connected`, `streaming` (+171 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 417 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **116 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Foundation` connect `Foundation` to `AppKit`, `VirtualDisplayManager`, `AirCatchClient/SharedModels.swift`, `NetworkHealthMonitor`, `VideoDecoder`, `AirCatchHost/SharedModels.swift`, `ScreenStreamer.swift`?**
  _High betweenness centrality (0.278) - this node is a cross-community bridge._
- **Why does `ClientManager` connect `ClientManager` to `Foundation`, `UDPStreamProcessor`, `.handleTCPPacket`, `Int`, `MouseHandlingView`, `View`, `BonjourBrowser`, `MetalVideoRenderer`, `AirCatchClient/SharedModels.swift`, `ConnectionState`, `.setStreamingStateIfNeeded`, `ConnectionOption`, `NetworkHealthMonitor`, `Bool`?**
  _High betweenness centrality (0.197) - this node is a cross-community bridge._
- **Why does `HostManager` connect `HostManager` to `Foundation`, `ScreenStreamer`, `NetworkHealthMonitor`, `MPCAirCatchHost`, `HostView`?**
  _High betweenness centrality (0.117) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `ClientManager` (e.g. with `BonjourBrowser` and `.body`) actually correct?**
  _`ClientManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 3 inferred relationships involving `HostManager` (e.g. with `BonjourAdvertiser` and `MPCAirCatchHost`) actually correct?**
  _`HostManager` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `disconnected`, `discovering`, `connecting` to the rest of the system?**
  _176 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `HostManager` be split into smaller, more focused modules?**
  _Cohesion score 0.08 - nodes in this community are weakly interconnected._