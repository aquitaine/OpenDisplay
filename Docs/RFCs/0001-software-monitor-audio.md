# RFC 0001: Software volume for HDMI/DisplayPort audio

- Status: Proposed
- Author: Farzad Hashemi
- Created: 2026-11-04

## Motivation and behavior

Some HDMI/DisplayPort audio endpoints do not expose an adjustable system volume
to macOS. On the reported HDMI monitor, audio consequently plays at full level
and the normal volume keys cannot attenuate it. DDC volume is not available on
every monitor. Add an explicit, session-only software volume option under
Settings → Health & Recovery → Media keys.

Select the monitor in macOS Sound Output, then enable the option. The slider and
F10/F11/F12 control mute and attenuation; media keys require Accessibility
permission and some keyboards require Fn. The gain begins at unity and never
amplifies above unity. macOS requests System Audio Recording permission only
when processing is enabled. Audio stays in memory and is not saved or uploaded;
the microphone is not used.

## Design and compatibility

`MonitorAudioController` owns a private, device-scoped Core Audio process tap,
private aggregate device and IOProc. The tap excludes this process and mutes its
original path only while tapped. Output is rendered back to the physical monitor
with a one-buffer gain ramp. No HAL driver is installed. The gain path does not
replace the system default output. Only one stereo Float32 PCM stream with
matching input/output layouts and sample rates is supported.

The feature uses public APIs on macOS 14.2 or later; availability checks retain
the app's existing macOS deployment target. It is included in both build flavors.
No persistent feature enablement, provider interface or serialized schema changes
are introduced. The separate speaker-fallback preference uses UserDefaults.

## Threat and recovery review requested

- Permission denial, unsupported formats and partial startup failures unwind the
  IOProc, aggregate and tap; the original audio path is restored. Disabling the
  option and quitting also tear down processing. Normal audio may return at the
  monitor's full hardware volume; software attenuation is not a hardware limiter.
- The real-time callback allocates no buffers and uses a nonblocking gain read.
  Malformed buffers are silenced and reported to a watchdog. Missing/stalled
  callbacks suspend processing and trigger bounded retries.
- Route changes suspend the managed path. Reconnecting the same device UID
  rebuilds processing after a settling interval, retaining gain and mute. Retry
  backoff is bounded. Software volume must be re-enabled after app relaunch.
- Optional speaker fallback selects a verified built-in speaker endpoint only
  when the missing monitor remains the default or no default exists. A working
  headphone, USB or Bluetooth route is preserved. Reconnection can return from
  the built-in route observed immediately after unplugging to the same monitor.
  Polling cannot distinguish every simultaneous manual route change; hardware
  validation should include manual output selection during unplug/replug.
- Speaker identification currently depends on a built-in device name containing
  “speaker”; localized names may safely result in no fallback. No microphone or
  system-alert output is changed.

## Validation and remaining work

The smoke suite exercises stereo layouts, gain ramp/mute, finite bounded gain,
invalid layouts, callback stalls, route preservation and reconnect retry policy.
Run `bash scripts/test-monitor-audio.sh <Xcode Build/Products/Debug>` after building.
Initial hardware volume control was reported working. Physical cable recovery
was subsequently revised; repeat physical reconnect, permission refusal,
sleep/wake and sustained playback tests before release. Latency, protected audio
and applications using non-default explicit output routes need further coverage.

This is original source contributed under GPL-3.0-or-later. No proprietary source,
UI or assets were used. Maintainer threat/recovery review is requested before
merging the audio-capture path.
