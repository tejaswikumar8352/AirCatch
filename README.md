# AirCatch

AirCatch is a two‑app system that streams a Mac screen to an iPad with low latency, plus an optional relay server for Internet (remote) sessions. It combines ScreenCaptureKit + VideoToolbox (macOS) with VideoToolbox + Metal (iPad), and sends mouse/keyboard/touch input back to the Mac.

## Components

- **AirCatchHost (macOS)**: Menu bar app that captures the Mac display, encodes video (HEVC/H.264), and injects input events. Uses Bonjour + MultipeerConnectivity for local discovery and a WebSocket relay for remote sessions.
- **AirCatchClient (iPadOS)**: iPad app that discovers hosts, connects with a PIN, decodes video in hardware, renders via Metal, and sends touch/keyboard/scroll input. Optional audio playback.
- **RemoteRelayServer (Node.js)**: WebSocket relay used only for Remote mode. It pairs a host and client by session ID (PIN) and relays control + media messages.

## Key Features

- **Low‑latency video**: HEVC by default with 60 FPS local presets (Performance/Balanced/Pro). Remote mode uses HEVC Main (8‑bit) with 30 FPS and adaptive bitrate.
- **Input control**: Touch, right‑click, double‑click, drag, scroll, pinch‑zoom, keyboard input, media keys, and voice typing.
- **Audio streaming**: Optional host audio capture and playback on the client.
- **Local discovery**: Bonjour service types `_aircatch._udp.` and `_aircatch._tcp.` with TXT metadata, plus MultipeerConnectivity (`aircatch`) for close‑range P2P.
- **Remote mode**: WebSocket relay with rate‑limited registration and binary relay for video.
- **End‑to‑end encryption**: AES‑256‑GCM with HKDF‑derived keys from the session PIN.

## How It Works (High Level)

### Discovery

- **Bonjour** advertises and discovers services on `_aircatch._udp.` and `_aircatch._tcp.`.
- **MultipeerConnectivity** advertises a P2P service named `aircatch` for close‑range discovery.

### Handshake & Transport

- The client sends a **handshake** containing device info, resolution, quality preset, requested audio/video, and PIN.
- The host verifies the PIN and replies with a **handshake ack** (actual capture resolution, FPS, bitrate, etc.).

**Local (LAN/P2P):**

- **TCP**: Control + handshake + input events.
- **UDP**: Video frames, usually chunked; optional retransmit (lossless mode) via `videoFrameChunkNack` requests.

**Remote (Internet):**

- Uses a **WebSocket relay** (`wss://aircatch-relay-teja.fly.dev/ws` by default).
- Host sends **full video frames over TCP channel** to reduce relay overhead.
- Audio is sent over the UDP channel (still via WebSocket relay messages).

### Encryption

- Both host and client derive a symmetric key from the session PIN using HKDF.
- Video/audio payloads are encrypted with AES‑256‑GCM before sending and decrypted on receipt.

## Configuration Defaults

From `AirCatchConfig`:

- UDP port: **5555**
- TCP port: **5556**
- Remote relay URL: **wss://aircatch-relay-teja.fly.dev/ws**
- Default local presets (HEVC): **10/20/30 Mbps @ 60 FPS**
- Remote defaults: **~6 Mbps @ 30 FPS**, adaptive in **4–10 Mbps** range
- Max UDP payload size: **1200 bytes**

## Permissions

### Client (iPad)

- **Local Network** + **Bonjour** (host discovery)
- **Microphone** + **Speech Recognition** (voice typing)

### Host (macOS)

- **Screen Recording** (screen capture)
- **Accessibility** (mouse/keyboard injection)

The host app prompts for these permissions on first launch.

## Build & Run

### Prerequisites

- macOS with Xcode installed
- iPad (or iPad Simulator) for the client
- Node.js 18+ if running the relay server

### Xcode

1. Open **AirCatch.xcodeproj** in Xcode.
2. Select **AirCatchHost** scheme and run on a Mac.
3. Select **AirCatchClient** scheme and run on an iPad.
4. On the iPad, choose a host, enter the 6‑character PIN shown on the Mac, and connect.

### Remote Relay Server (Optional)

The relay server is in `RemoteRelayServer/` and uses the `ws` library.

1. Install dependencies: `npm install`
2. Start: `npm start`
3. Set `AirCatchConfig.remoteRelayURL` in both client and host if you use a custom relay.

Fly.io config is included in `RemoteRelayServer/fly.toml`.

## Project Structure

```
AirCatch.xcodeproj/           Xcode project (schemes: AirCatchClient, AirCatchHost)
AirCatchClient/               iPad client app
AirCatchHost/                 macOS host app
RemoteRelayServer/            WebSocket relay server
ExportOptions.plist           Export configuration (Developer ID)
LICENSE                       MIT License
```

### AirCatchClient Highlights

- `ClientManager.swift`: connection orchestration, handshake, stream handling
- `NetworkManager.swift`: UDP/TCP client transport
- `RemoteTransport.swift`: WebSocket relay transport for remote mode
- `VideoDecoder.swift` + `MetalVideoView.swift`: hardware decode + Metal rendering
- `VideoStreamOverlay.swift`: video display + input overlay
- `MouseInputView.swift`, `KeyboardInputView.swift`, `MacKeyboardView.swift`: input capture
- `SpeechManager.swift`: voice typing
- `CryptoManager.swift`: AES‑GCM encryption/decryption

### AirCatchHost Highlights

- `HostManager.swift`: main host lifecycle + handshake + streaming control
- `ScreenStreamer.swift`: ScreenCaptureKit capture + VideoToolbox encoding + audio capture
- `NetworkManager.swift`: UDP/TCP server transport
- `RemoteTransportHost.swift`: relay transport for remote mode
- `InputInjector.swift`: mouse/keyboard/media‑key injection
- `BonjourAdvertiser.swift` + `MPCAirCatchHost.swift`: discovery + P2P
- `CryptoManager.swift`: AES‑GCM encryption

### RemoteRelayServer Highlights

- `server.js`: WebSocket relay with session pairing and rate limiting
- `Dockerfile`: container build
- `fly.toml`: Fly.io deployment config

## License

MIT License. See `LICENSE`.