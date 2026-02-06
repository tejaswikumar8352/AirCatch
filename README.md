# AirCatch

Turn your iPad into a wireless display for Mac with touch input and audio.

## What It Does

- Stream your Mac screen to iPad over WiFi or internet
- Control your Mac with touch gestures (tap, drag, scroll, pinch)
- Hear Mac audio on iPad (48kHz stereo)
- Create virtual displays matching iPad's native resolution

## Connection Modes

**Local (same network)**
- Uses AWDL or local WiFi
- 60fps, HEVC video, ~16 Mbps
- End-to-end encrypted

**Remote (anywhere)**
- Uses WebRTC through relay server
- 30fps, H.264 video, 4 Mbps cap
- Works over the internet

## Security

- PIN-based pairing (6-digit alphanumeric)
- Session tokens for seamless reconnection
- Local mode: AES-256-GCM encryption (E2EE)
- Remote mode: WebRTC DTLS/SRTP encryption
- Host restart invalidates all tokens

## Requirements

- Mac: macOS 13+ (Ventura)
- iPad: iPadOS 16+
- Xcode 15+ (to build)

## Setup

1. Open `AirCatch.xcodeproj` in Xcode
2. Build and run `AirCatchHost` on Mac
3. Build and run `AirCatchClient` on iPad
4. Grant permissions on Mac:
   - Screen Recording
   - Accessibility (for input)

## Connect

1. Launch host on Mac
2. Launch client on iPad
3. Enter the 6-digit PIN shown on Mac
4. Done. Future connections auto-reconnect.

## Remote Relay

Optional Node.js server for internet connections:

```
cd RemoteRelayServer
npm install && npm start
```

Listens on port 8080. Use wss:// with TLS in production.

## Project Layout

```
AirCatch/
├── AirCatchHost/       # Mac app
├── AirCatchClient/     # iPad app
├── RemoteRelayServer/  # Relay server
└── AirCatch.xcodeproj
```

## Troubleshooting

- No video → Check Screen Recording permission
- No input → Check Accessibility permission
- Remote fails → Check relay URL and room code

## License

MIT
