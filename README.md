# FanCtl (macOS)

Menu-bar fan control for Macs: CPU/GPU temperatures plus Auto, Manual and
temperature-curve modes per fan. Universal binary for Apple Silicon and Intel, macOS 13+.

## Install

1. Download `FanCtl-<version>.pkg` from the
   [latest release](https://github.com/venkateshguggilla/fanctl-macos/releases/latest)
   and open it. The installer puts `FanCtl.app` in `/Applications`, installs the root
   helper, and starts the app.
2. Click the fan icon in the menu bar.
3. Per fan pick **Auto**, **Manual** (fixed RPM) or **Curve** (min speed at the low
   temperature → max speed at the high one, following CPU or GPU temperature).

In Curve mode fan 0 follows the CPU and any other fan the GPU by default. Fanless Macs
(e.g. MacBook Air) show temperatures only.

To uninstall: **Helper → Uninstall…** in the panel, then delete `/Applications/FanCtl.app`.

## Build

```sh
./build.sh          # -> build/FanCtl.app (universal, Developer ID-signed if available)
./package.sh        # -> build/FanCtl-<version>.pkg
NOTARY_PROFILE=<profile> ./package.sh   # also notarize + staple
```

A locally built app can install the helper itself: **Install Helper…** in the panel asks
for your admin password and installs `fanctld` as a root LaunchDaemon
(`/Library/LaunchDaemons/local.fanctl.daemon.plist`); only root can write to the SMC.

## Safety

- RPM is always clamped to the firmware `F<n>Mn`/`F<n>Mx` range.
- `fanctld` returns a fan to Auto when the app that set it quits, crashes or disconnects,
  and returns all fans to Auto at startup and on SIGTERM (including uninstall).
- If firmware drops a fan back to Auto (e.g. after sleep), `fanctld` re-applies it.

## Status

- **Intel (verified on MacBookPro16,1, macOS 26):** sensor reading, and manual fan control
  through the helper (`F<n>Md` = 1 plus `F<n>Tg`; fan 0 reached a 3000 rpm target in about
  8 seconds and returned to Auto on `auto 0`).
- **Apple Silicon (untested):** temperatures come from the hottest `Tp*`/`Te*` (CPU) and
  `Tg*` (GPU) SMC sensors. Manual mode first sets the `Ftst` unlock key, then retries
  `F<n>Md` for up to 10 seconds while macOS releases the fans.

## Layout

| Path | What |
|---|---|
| `Sources/CSMC` | raw AppleSMC user-client calls |
| `Sources/SMCKit` | typed key read/write, fan/temperature readers |
| `Sources/fanctld` | root helper (Unix socket `/var/run/fanctld.sock`, owner-only) |
| `Sources/FanCtl` | SwiftUI menu-bar app |
| `scripts/` | helper install / uninstall (run by the app via an admin prompt) |

`fanctld --probe` prints fans and temperatures without changing anything.
Helper log: `/var/log/fanctld.log`.
