#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
products="${1:?Pass Xcode Build/Products/Debug as the first argument}"
mkdir -p "$root/build/monitor-audio/tests" "$root/build/monitor-audio/module-cache"
xcrun swiftc -swift-version 6 -module-cache-path "$root/build/monitor-audio/module-cache" \
  -F "$products" -framework TopologyCore -framework DisplayDomain \
  -framework ProviderInterfaces -framework SceneEngine -framework AutomationSchema \
  -Xlinker -rpath -Xlinker "$products" \
  "$root/Apps/OpenDisplay/Sources/AudioOutputInfo.swift" \
  "$root/Apps/OpenDisplay/Sources/MonitorAudioController.swift" \
  "$root/Tests/MonitorAudioSmoke/main.swift" \
  -o "$root/build/monitor-audio/tests/monitor-audio-smoke"
"$root/build/monitor-audio/tests/monitor-audio-smoke"
