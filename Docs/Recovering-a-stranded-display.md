# Recovering a display that won't come back

This page is for one specific, rare situation: you turned a display off with OpenDisplay, asked
for it back, and it never returned — the monitor is plugged in and powered (it may even say it has
a signal) but shows black, and macOS doesn't list it anywhere, not even in System Information.
OpenDisplay marks this on the display's card as **Didn't come back on**.

Tracked in [issue #40](https://github.com/aquitaine/OpenDisplay/issues/40). The cause is not fully
understood yet. What is known: macOS keeps a saved configuration for every display it has seen and
restores it when the display connects. If a saved entry can no longer be applied, macOS gives up
instead of falling back to a safe mode, so the display never appears. Nothing inside OpenDisplay
can clear that state; the steps below can.

## First, rule out the ordinary causes

1. Check the cable and that the monitor is on the right input. For the built-in display, make
   sure the lid is open — a closed lid keeps it off no matter what any app asks.
2. In OpenDisplay's menu, click **Try again** on the display's card, then **Reconnect all**.
3. Quit OpenDisplay completely. Displays it turned off are released when it exits.
4. Unplug the display, wait ten seconds, plug it back in.

If the display is back, stop here.

## Reset macOS's saved display configuration

This makes macOS forget its saved settings for **all** displays — arrangement, resolution, refresh
rate, rotation, and mirroring — and rebuild them from scratch. You will need to arrange your
displays again afterwards. It does not touch OpenDisplay's own settings.

1. Save your work and unplug every external display.
2. Open Terminal and run these two commands. The second asks for your password.

   ```bash
   rm -f ~/Library/Preferences/ByHost/com.apple.windowserver.displays*.plist
   ```

   ```bash
   sudo rm -f /Library/Preferences/com.apple.windowserver*.plist
   ```

3. **Restart the Mac immediately** (Apple menu → Restart). Do not log out first, and do not run
   `killall Dock` or `killall WindowServer` — macOS holds this configuration in memory and writes
   it straight back if anything gives it the chance, which undoes the reset.
4. After the restart, plug the display back in.

This procedure was worked out and verified by the reporter of issue #40.

## A workaround that looks like a fix

On some monitors, changing a signal setting in the monitor's own menu (Samsung's *Input Signal
Plus*, for example) makes the display reappear. That works because the monitor then identifies
itself differently, so the bad saved entry no longer matches — but it usually costs you the high
refresh-rate mode. Use it to get a picture if you need one, then do the reset above.

## Before you reset: export diagnostics

The reset destroys the evidence of what went wrong, so please capture it first. It takes a few
seconds and nothing is sent anywhere.

- In the app: **Settings → Health & Recovery → Diagnostics → Export Diagnostics…**
- Or, if the app's window is on the display that went missing, in Terminal:

  ```bash
  /Applications/OpenDisplay.app/Contents/Helpers/opendisplay diagnose --bundle
  ```

Either one saves `OpenDisplay-diagnostics-<date>.zip` to your Desktop. Attach it to
[issue #40](https://github.com/aquitaine/OpenDisplay/issues/40). **Export while the display is
still missing** — that is the state we have never been able to look at.

The file contains:

- OpenDisplay's own records: a timeline of what macOS reported about your displays each time
  something changed, its audit log, the displays it turned off, and its settings (with location
  and app presets removed).
- macOS's saved display configuration as it is now, and as OpenDisplay copied it just before each
  of your last five disconnects.
- What macOS reports about the displays, the DisplayPort link, and Thunderbolt devices. This
  includes model names and serial numbers of your displays and docks.
- The last 30 minutes of display-related system log lines.

It does not contain window titles, file names, screen contents, or your location. It is a plain
zip; you can open it and look before sharing.
