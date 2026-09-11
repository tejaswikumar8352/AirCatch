# AirCatch

**Turn your iPad into a wireless second display for your Mac** — stream your screen, control your Mac with touch and Magic Keyboard, and connect anywhere over Tailscale.

AirCatch is an open-source implementation of Apple Sidecar-style functionality built on [Network.framework](https://developer.apple.com/documentation/network), ScreenCaptureKit, and VideoToolbox. It captures your Mac's screen with hardware HEVC encoding, streams it to an iPad with sub-frame latency, and sends input back — all end-to-end encrypted.

### Rendering Display Output That Actually Looks Retina

This is the part Sidecar gets right and most clones get wrong, so AirCatch does the hard version on purpose:

- The host **creates a full virtual display** using the private-but-real `CGVirtualDisplay` API (runtime-loaded via `NSClassFromString("CGVirtualDisplay")` + KVC, with a `displayWithDescriptor:` fallback for other macOS versions) instead of just mirroring your existing screen.
- The virtual display is created at the iPad's **physical** pixel size (e.g. 2732 × 2048 for a 12.9" Pro), with `hiDPI = true` — so macOS sees it as a real Retina monitor and renders crisp vector text at logical 1366 × 1024 scaled ×2, never a blurry upscaled framebuffer.
- The physical size is back-computed to **~220 PPI** (`VirtualDisplayManager.swift:155-159`) so macOS's display-size heuristics behave like a real panel and don't try to be "helpful."
- **Per-iPad model detection** (`SharedModels.swift:594-725`): a hardware-ID table (`iPad8,5`–`iPad16,6`, plus `14,x`/`16,x` for M-series iPads) maps the connecting iPad to a `iPadDisplayPreset` — Pro 12.9", Pro 11", Air 10.9", mini 6, standard — picking the right aspect ratio and logical/pixel pair automatically. Unknown models fall back to resolution-based matching or a sensible generic preset.

### Video Encoding That Isn't Just "Whatever H.264 Does"

- **HEVC via VideoToolbox hardware encoder** (`ScreenStreamer.swift:235-339`). We try **HEVC *Main10* (10-bit, 4:2:0)** first and only drop to 8-bit Main if the encoder refuses it. `RequireHardwareAcceleratedVideoEncoder = true` — no software fallback that would melt your CPU.
- Latency-tuned: `RealTime` mode, `MaxFrameDelayCount = 1`, `AllowFrameReordering = false`, ~1s keyframe interval.
- Frames are packetized zero-copy (`IOSurface`-backed) and reassembled on the client, where `VideoDecoder.swift` runs a hardware `VTDecompressionSession` (10-bit-aware) straight into a `MetalView` for zero-CPU-copy presentation.

### Touch Input That Actually Lines Up With What You See

A hand-rolled `UIHoverGestureRecognizer`-aware gesture layer on the iPad normalizes touch coordinates to 0-1 and ships them (touch/scroll/pinch/media keys) as JSON control packets. The magic is on the receiving end:

- `HostManager.swift:1344-1365` — when the *visible* aspect ratio doesn't match the *physical* Mac display (letterboxing/pillarboxing from client-fit rendering), AirCatch **corrects the normalized coordinate by the bar offset** before injection, so the cursor lands where you tapped, not where the stretched frame says it should.
- Multi-stage hard candidate for macOS mapping: touch events map cleanly through the virtual-display pixel-perfect path (no remapping needed at all when the display matches the iPad exactly), and only fall back to aspect-correction when mirroring a physical main display.
- Magic Keyboard + trackpad gestures are captured via a full HID-usage → macOS virtual-keycode translation table (letters, digits, modifiers, F1–F12, arrows, keypad) so Command/Ctrl/Option shortcuts work end-to-end.

---

## Why AirCatch?

| Sidecar | AirCatch |
|---|---|
| Apple-only, closed | Open source, inspectable |
| Same Wi-Fi only | **Tailscale direct-IP over any network** |
| Fixed settings | Adaptive bitrate, custom display presets |
| Requires Apple ecosystem lock-in | Pair once, reconnect with one tap forever |

---

## How It Works

```
┌──────────────────┐                      ┌──────────────────┐
│   AirCatchHost   │  HEVC over UDP 5555  │  AirCatchClient  │
│   (macOS app)    │ ◄──────────────────► │  (iPad app)      │
│   Captures +     │  Control over TCP    │  Decodes +       │
│   encodes screen │  5556 + auth/keys    │  sends input     │
└──────────────────┘                      └──────────────────┘
```

- **Video** — ScreenCaptureKit captures the display; VideoToolbox compresses to HEVC (hardware encoder, attempts Main10 first, falls back to 8-bit); chunks are sent as AES-256-GCM-encrypted UDP datagrams (1200-byte payload, reassembly + optional NACK retransmit on the client).
- **Input** — iPad touch, trackpad, pinch, scroll, and Magic Keyboard presses are wrapped in small JSON control packets over TCP and injected on the Mac as native `CGEvent`s.
- **Control channel** — handshake (auth challenge-response), ping/pong latency probes, quality reports for adaptive bitrate, and disconnect signaling all ride the same TCP socket.

## Security Model

- **AES-256-GCM** encrypts every video/audio/control payload on the wire — the key is derived with **PBKDF2-HMAC-SHA256, 200,000 iterations** from a 6-character pairing PIN.
- **Challenge-response PIN auth** — the PIN itself is never sent over the wire; the client proves knowledge via `HMAC-SHA256(challenge, PBKDF2-derived-authKey)`.
- **Session tokens** — after first successful pairing, the host issues a 256-bit token (24 h TTL, sliding) stored in the iPad's Keychain, so subsequent reconnects need no PIN.
- **No plaintext PIN fallback** — rejected clients get `pairingFailed`; the TLS-of-the-relay days (and the relay server itself) are gone.

## Features

- **One-tap pairing (Sunshine/Moonlight-style)**: pair once with the PIN → the host and PIN are persisted (Keychain), and **Paired Hosts appear on the client home screen for one-tap reconnect**. The host PIN persists across app restarts, so pairings survive.
- **Tailscale / direct-IP support**: a "Manual Connect" flow lets you enter a `100.x.y.z` Tailscale address (or any reachable IP) — no Bonjour needed. The host binds its listeners to **all interfaces** so it accepts connections from the `utun` tunnel, not just the local Wi-Fi.
- **Magic Keyboard + trackpad**: full hardware-keyboard capture (all modifiers, function keys, arrows; HID → macOS keycode mapping), two-finger/scroll-wheel scrolling, pinch-to-zoom, and long-press/secondary-click gestures.
- **Sidecar-like virtual display** (host): optionally creates a private-API `CGVirtualDisplay` matching the iPad's physical resolution for pixel-perfect output.
- **Adaptive bitrate**: client reports quality; host steps bitrate down on congestion and back up after a cooldown.
- **Audio**: optional system-audio capture (48 kHz stereo PCM) with drift-corrected playback on the iPad.

## Project Structure

```
AirCatch/
├── AirCatchHost/          # macOS app (menu bar host)
│   ├── HostManager.swift        # Orchestrates auth, capture, broadcasting
│   ├── ScreenStreamer.swift     # ScreenCaptureKit → VideoToolbox HEVC
│   ├── NetworkManager.swift     # UDP :5555 + TCP :5556 listeners (all interfaces)
│   ├── InputInjector.swift      # CGEvent mouse/keyboard/media injection
│   ├── CryptoManager.swift      # AES-GCM + PBKDF2 + challenge-response
│   ├── VirtualDisplayManager.swift / DisplayManager.swift
│   └── SharedModels.swift       # Packet types, handshake models, Bitrate config
│
├── AirCatchClient/        # iPadOS app (receiver + controller)
│   ├── ClientManager.swift      # Connection orchestration + pairing store
│   ├── NetworkManager.swift     # UDP/TCP client sockets
│   ├── ContentView.swift        # UI: paired hosts, discover, manual connect
│   ├── MouseInputView.swift     # Touch/trackpad/keyboard capture
│   ├── VideoStreamOverlay.swift # Fullscreen stream view
│   ├── VideoDecoder.swift / MetalVideoView.swift / AudioPlayer.swift
│   └── CryptoManager.swift      # Client side of the crypto handshake
│
├── AirCatch.xcodeproj/    # Xcode project (two app targets, iOS 17+ / macOS 15.6+)
├── graphify-out/          # Code-graph analysis (see below)
└── ExportOptions.plist    # Developer-ID export settings for host distribution
```

## Design Notes: Why This Looks Right and Reads Fast

### Video Pipeline — Hardware HEVC, End to End

This project does not ship H.264 because it's "good enough." No, let's get real:

- **HEVC Main10 first, HEVC Main fallback** (`ScreenStreamer.swift:280-292`): we try 10-bit HEVC Main first (`VTProfileLevel_HEVC_Main10_AutoLevel`) because the color fidelity + bitrate efficiency at 4K-class frame sizes beats 8-bit by a wide margin, and only downgrade for older Macs. The encoder is told *require* hardware acceleration (`RequireHardwareAcceleratedVideoEncoder = true`), so we never silently spin up a power-melting software encoder mid-stream.
- **Zero-copy**: ScreenCaptureKit → `VTCompressionSession` (IOSurface-backed) → chunking → VideoToolbox decompression on the iPad (`VideoDecoder.swift`) → Metal textures (`CVMetalTextureCache`). The frame never makes a CPU round-trip.
- **Low-latency encoder settings**: `RealTime = true`, `MaxFrameDelayCount = 1`, `AllowFrameReordering = false` — no frame bucketing, no B-frame look-ahead.
- **Color correctness**: P3 primaries with Rec.709 transfer, full-range forced via the (undocumented) `"FullRangeVideo"` VideoToolbox property, HDR metadata preserved on 10-bit streams. Text stays sharp, gradients don't band.

### The Virtual Display Story — Why Text Doesn't Look Like Soup

Here's the part that took real effort:

After pairing, the host creates a **private-API virtual display** (`CGVirtualDisplay`) sized to the iPad's *physical* resolution with `hiDPI = true`:

- Created at full pixel resolution (e.g., 2732 × 2048 for an iPad Pro 12.9")
- Logical points = half of that with ×2 Retina — exactly how Apple does Sidecar internally
- An ~220 PPI physical size is back-computed so `NSDeviceDescription`/`NSScreen` heuristics treat it like a real display instead of defaulting to blurry scaling
- macOS's WindowServer happily sends a HiDPI framebuffer, which we encode at full resolution and the iPad displays pixel-for-pixel

The payoff: text on the iPad is as crisp as it is in the Mac's own Finder — because it *is* rendering at Retina densities, not stretching a 1080p bitmap onto a 2732×2048 panel.

### Precision Input — The Math That Makes Touches Land Right

The naive approach (send normalized 0-1 touch coordinates → map to screen space) breaks in well-known ways:
- When the host display aspect ratio ≠ the iPad's, the video is letterboxed on the client. A tap at `(0.2, 0.3)` on the *letterboxed* frame is not at `(0.2, 0.3)` on the *real* display — there's an unused band at top/bottom (or left/right).
- A second problem: input is queued for latency reasons, so by the time macOS gets it the event could be stale.

Fix in `HostManager.swift:1344-1365`:

```swift
let hostAspect = hostW / hostH
let clientAspect = Double(clientW) / Double(clientH)
if hostAspect > clientAspect {
    let coverageH = clientAspect / hostAspect
    let barH = (1.0 - coverageH) / 2.0         // fraction of frame that's letterbox
    finalNormY = (touch.normalizedY - barH) / coverageH
} else {
    let coverageW = hostAspect / clientAspect
    let barW = (1.0 - coverageW) / 2.0
    finalNormX = (touch.normalizedX - barW) / coverageW
}
```

Combined with InputStateCache snapshot reads (0 queue-stall) and a 100 ms stale-event gate on a dedicated `.userInteractive` queue, pointers land where you tap, and dropped-late events don't cause ghost drags.

## Given the above, what else is worth showing off?

- One-tap pairing (Sunshine/Moonlight-style) — Keychain-persisted PIN + session tokens that survive host restarts
- AES-256-GCM end-to-end with PBKDF2-HMAC-SHA256 (200k iterations) key derivation from a 6-char PIN — the PIN never crosses the wire (challenge-response with HMAC-SHA256)
- Adaptive bitrate (drops on congestion fast, climbs back after a 4s cooldown to avoid oscillation)
- Tailscale-direct manual-IP connect for remote streaming (no Bonjour needed)
- Magic Keyboard + trackpad, full mod/shortcut/fn-key support

## Requirements

- macOS 15.6+ (host), iPadOS 17+ (client), Xcode 16/26
- Host needs: **Accessibility** (input injection), **Screen Recording** permissions
- No third-party dependencies — pure first-party Apple frameworks

## Getting Started

1. Clone and open `AirCatch.xcodeproj` in Xcode.
2. Build and run **AirCatchHost** on your Mac — it shows a 6-character PIN.
3. Build **AirCatchClient** on your iPad (device or simulator).
4. Pair once: either tap a discovered host on the same network or use **Manual Connect** and enter the Mac's IP + PIN.
5. From then on, tap the host under **Paired Hosts** — no credentials needed.

### Connecting over Tailscale
1. Install and start Tailscale on both the Mac and the iPad.
2. On the client, tap **Manual Connect** → enter the Mac's `100.x.y.z` Tailscale address + PIN.
3. The connection routes through the `utun0` interface exactly like a LAN session — same encryption, same protocol.
   - Note: Bonjour discovery is intentionally not relied on here (Tailscale blocks mDNS); direct-IP connection is the supported remote path.

## Code Graph (graphify)

The repo includes a [Graphify](https://github.com/…)(v0.9.57) knowledge graph of the whole codebase at `graphify-out/`:

- `graphify-out/GRAPH_REPORT.md` — human-readable structural report
- `graphify-out/graph.html` — **interactive visualization** (open in a browser; uses vis-network)
- `graphify-out/graph.json` — raw node/edge data for tooling
- `graphify-out/manifest.json` + `cache/` — incremental freshness tracking keyed to `git rev-parse HEAD`

Regenerate after code changes with `graphify update .` (no API cost).

## Roadmap / Ideas

- Public-key-pinned pairing (per-device certificates instead of PIN rotation)
- USB-C / wired connection mode for zero-network-latency gaming
- HDR metadata preservation end-to-end

## License

MIT — use it, fork it, ship it.

---

*Built with ScreenCaptureKit, VideoToolbox, Network.framework, SwiftUI, and a healthy disrespect for paying for a second screen.*
