AirCatch
======

AirCatch is a Mac + iPad app pair that turns your iPad into a fast, high-quality wireless display for your Mac, with optional reverse control. The goal is simple: keep the stream sharp (Retina-class), keep motion smooth (60fps), and keep interaction responsive.

What you get
------------

On the Mac, AirCatchHost captures the screen using ScreenCaptureKit, encodes it with VideoToolbox, and streams it over the network. On the iPad, AirCatchClient receives the stream, reassembles frames, decodes them, and renders with Metal.

AirCatch also supports input back to the Mac: taps, drags, scrolling, right-click, and keyboard input.

Video and rendering
-------------------

AirCatch is built around a high-throughput, low-copy video pipeline. Frames are encoded as HEVC (including Main 4:2:2 10‑bit when supported) and sent at 60fps. On the client side, frames are decoded and displayed with a Metal-backed view.

Networking
----------

Discovery uses Bonjour with the service type `_aircatch._udp`. Video frames are transported as chunked UDP packets for throughput and low latency, while control traffic (handshake, pairing, input) goes over a reliable channel.

Connections over the internet or VPN (like Tailscale) are supported via Remote Connect. You enter the host IP manually, and the client automatically switches to the Performance preset (25 Mbps) to accommodate upload constraints.


Input and on-screen keyboard
----------------------------

AirCatch maps iPad touch gestures into macOS input events on the host. For typing, the client includes a Mac-style on-screen keyboard overlay that can be moved and resized. The keyboard UI is translucent so the desktop remains visible underneath, and the keycaps are styled dark with white legends.

The function row follows Apple’s Mac keyboard layout for F1 through F12. For media/system keys (brightness, volume, playback), the host injects AUX control button events using `NSEvent.otherEvent(with: .systemDefined, subtype: 8, ...)`.

Quality presets
---------------

AirCatch ships with a few presets to make it easy to tune for different networks. All presets target 60fps; the main difference is bitrate.

| Preset | Target Bitrate | When to use it |
| --- | ---: | --- |
| Performance | 25 Mbps | Congested Wi‑Fi, longer range |
| Balanced | 45 Mbps | Default for typical 5GHz Wi‑Fi |
| Quality | 80 Mbps | Strong Wi‑Fi 6/6E or wired |

How it works (at a glance)
--------------------------

The client discovers a host, connects, and sends a handshake describing its screen and streaming preferences. The host starts capture and encoding, then streams chunked frames. Each UDP chunk includes a small header so the client can reassemble complete frames before decoding.

Build
-----

Host (macOS):

```bash
xcodebuild -scheme AirCatchHost -destination 'platform=macOS'
```

Client (iPadOS):

```bash
xcodebuild -scheme AirCatchClient -destination 'generic/platform=iOS'
```

Permissions
-----------

On macOS, AirCatchHost needs Accessibility permission to inject input events (System Settings → Privacy & Security → Accessibility). On iPadOS, AirCatchClient needs Local Network permission for discovery and connections.

Picture in Picture (PiP)
------------------------

The client includes PiP support. On iOS 18 and later, it uses `sampleBufferRenderer.enqueue(...)`; earlier iOS versions use the legacy enqueue path.

DriverKit (optional)
--------------------

This repo also includes an optional DriverKit virtual display component. If you want to use that path, see AirCatchDisplayDriver/README.md.

License
-------

Private & Proprietary. Copyright © 2026 Teja Chowdary.
