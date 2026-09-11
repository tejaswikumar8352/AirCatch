import re

with open('/Users/tej/Downloads/AirCatch/AirCatchHost/HostManager.swift', 'r') as f:
    content = f.read()

# 1. Extract InputStateCache
cache_class_pattern = r"(\s*)private final class InputStateCache: @unchecked Sendable \{.*?\n\1\}\n"
match = re.search(cache_class_pattern, content, re.DOTALL)
if match:
    cache_class_code = match.group(0).strip() + "\n\n"
    content = content[:match.start()] + content[match.end():]
    
    # insert before @MainActor \n final class HostManager
    main_actor_idx = content.find("@MainActor\nfinal class HostManager")
    content = content[:main_actor_idx] + cache_class_code + content[main_actor_idx:]

# 2. Fix the unused cachedState in handleScrollEvent
content = content.replace("        let cachedState = cachedInputStateSnapshot()\n", "")

# 3. Fix the implicit retain cycle warnings (lines 265, 272, 277)
# For the UDP listener
content = content.replace("try networkManager.startUDPListener(port: AirCatchConfig.udpPort) { [weak self] packet, endpoint in\n                    self?.handleIncomingPacket(packet, from: endpoint)",
                          "try networkManager.startUDPListener(port: AirCatchConfig.udpPort) { packet, endpoint in\n                    self.handleIncomingPacket(packet, from: endpoint)")

# For the TCP listener
content = content.replace("onConnection: { [weak self] connection in\n                        Task { @MainActor in\n                            self?.sendTCPAuthChallenge(to: connection)\n                        }",
                          "onConnection: { connection in\n                        Task { @MainActor in\n                            self.sendTCPAuthChallenge(to: connection)\n                        }")

content = content.replace("onPacket: { [weak self] packet, connection in\n                        self?.handleTCPPacket(packet, from: connection)\n                    }",
                          "onPacket: { packet, connection in\n                        self.handleTCPPacket(packet, from: connection)\n                    }")


with open('/Users/tej/Downloads/AirCatch/AirCatchHost/HostManager.swift', 'w') as f:
    f.write(content)
