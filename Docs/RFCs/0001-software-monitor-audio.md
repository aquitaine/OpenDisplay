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
  Malformed buffers are silenced and reported to a watchdog. HAL device liveness
  determines automatic recovery; callback silence alone is not failure. Running
  state is checked on volume interaction, so an idle HAL engine does not cause
  repeated teardown. Dead or stopped routes trigger bounded retries.
- Route changes suspend the managed path. Reconnecting the same device UID
  rebuilds processing after a settling interval, retaining gain and mute. Retry
  backoff is bounded. Each volume key/slider action checks the route and can
  re-arm exhausted retries without resetting gain or mute. Software volume must
  be re-enabled after app relaunch.
- Optional speaker fallback selects a verified built-in speaker endpoint only
  when the missing monitor remains the default or no default exists. A working
  headphone, USB or Bluetooth route is preserved. Reconnection preserves the currently selected output; monitor processing resumes
  only when that monitor is selected again.
  Polling cannot distinguish every simultaneous manual route change; hardware
  validation should include manual output selection during unplug/replug.
- Speaker identification currently depends on a built-in device name containing
  “speaker”; localized names may safely result in no fallback. No microphone or
  system-alert output is changed.

## Validation and remaining work

The smoke suite exercises stereo layouts, gain ramp/mute, finite bounded gain,
invalid layouts, idle callback silence, route preservation and reconnect retry policy.
Run `bash scripts/test-monitor-audio.sh <Xcode Build/Products/Debug>` after building.
Initial hardware volume control was reported working. Physical cable recovery
was subsequently revised; repeat physical reconnect, permission refusal,
sleep/wake and sustained playback tests before release. Latency, protected audio
and applications using non-default explicit output routes need further coverage.

This is original source contributed under GPL-3.0-or-later. No proprietary source,
UI or assets were used. Maintainer threat/recovery review is requested before
merging the audio-capture path.

## Local recovery revision

The menu-bar and display volume controls use the same software gain as the keys
when the selected monitor is the managed audio route, including when DDC volume
is unavailable. Nested controller changes notify the application model, so the
menu value follows keys and the settings slider. Manual disablement is respected;
a volume key never enables system-audio capture without prior session opt-in.
Recovery runs in common run-loop modes and rebuilds the session after wake.
A locally packaged app can set `OpenDisplayDisableUpdates` in its Info.plist to
avoid being replaced by an upstream binary without this feature.

Logical display disconnect now captures its current audio route before removing
the display, and switches that route to verified built-in speakers only after
the coordinator commits. A concurrent choice of another output is preserved.
The transfer is explicit for Turn Off, independent of the physical-unplug
fallback preference, because the logical-off endpoint can remain enumerated.

Reconnect replay guard: output is zeroed before every callback; duplicate or
backwards valid input sample timestamps are discarded. Retiring a processor
closes its render gate before HAL stop/destroy, preventing callbacks still in
flight from copying old PCM. A default-output listener requests route checks
without waiting for the polling timer. Hardware reconnect during playback still
requires validation; these guards do not prove the hardware symptom resolved.

Revision 6 changes logical disconnect ordering: close the render gate and send
silent buffers for 150 ms while the physical link is still active, select built-in
speakers if the original output is still selected, then destroy the tap before
requesting display removal. Suppress reconstruction while logically offline.
After the same display is verified lit, re-arm recovery and return only from the
remembered built-in route; another current output is preserved. A rejected
disconnect also re-arms recovery. This restores automatic monitor selection
removed in revision 5. The renderer regression verifies quiescing before HAL
teardown, but hardware buffer drain and reconnect playback still need validation.

Revision 7 requires eight actual zero-output callbacks before logical display
removal (up to 500 ms). A timeout keeps the display on and reports an error.
HAL stop/destroy results are checked; a failed teardown retains ownership and
blocks construction of a second processor. This makes previously hidden failures
visible rather than claiming the route was drained after a fixed delay.
Hardware testing is still necessary to establish whether the repeated-audio
symptom is eliminated on this monitor.

Settings also offers per-display power toggle shortcuts, Control–Option–Command–
Shift plus 1…9, persisted in UserDefaults by stable display identity. The normal
coordinator and verified reconnect path are reused; the last active screen is
protected. Binding conflicts inside the app are rejected and OS registration
failure is shown. Reconnect All remains Control–Option–Command–R.

Revision 8 unifies reconnect notification for user and automatic recovery paths.
Audio reattachment waits for the monitor endpoint and retries after delayed HAL
availability. Before selecting the returning endpoint, a fresh private route
renders confirmed zero-output buffers on that link while the main sound remains
on the Mac. That temporary route is retired before restoring normal processing.
Another selected headphone/USB route is preserved after asynchronous work.
These changes require live monitor validation: persistence after app exit and
cessation after a cable reset implicate the downstream link but do not identify
its precise failure mode. Successful renderer tests do not establish resolution
of that hardware symptom.

Slider readouts reserve enough horizontal width for 100%, disallow line wrapping,
and preserve their intrinsic horizontal size for both brightness and volume.

Revision 9 adds independent physical audio-attach routing. A pending endpoint UID
survives delayed transition to built-in speakers and does not depend on software
volume enablement or the old three-second fallback window. Selection waits for
one second of endpoint availability, rechecks the actual speaker route before
writing and retries failed writes. Another external/headphone route cancels the
pending selection. Multiple simultaneous arrivals require the previously used
monitor to disambiguate. Logical-off recovery retains its silent-priming path.
Tests cover delayed fallback, manual headphones, ambiguous arrivals and successful
selection. Physical hardware testing remains required.
