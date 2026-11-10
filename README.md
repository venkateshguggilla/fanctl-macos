# FanCtl (macOS)

Menu-bar fan control for the MacBook Pro 16" 2019 (MacBookPro16,1, Intel + T2).

## Build

```sh
./build.sh          # -> build/FanCtl.app
```

## Use

1. Open `build/FanCtl.app` — a fan icon with the CPU temperature appears in the menu bar.
   Temperatures and fan speeds work immediately (read-only).
2. Click **Install Helper…** once and enter your admin password. This installs
   `fanctld` as a root LaunchDaemon (`/Library/LaunchDaemons/local.fanctl.daemon.plist`);
   only root can write to the SMC.
3. Per fan pick **Auto**, **Manual** (fixed RPM) or **Curve** (min speed at the low
   temperature → max speed at the high one, following CPU or GPU temperature).

The two fans are left/right fans on a shared heat-pipe; by default fan 0 follows the
CPU and fan 1 the GPU in Curve mode.

## Safety

- RPM is always clamped to the firmware `F<n>Mn`/`F<n>Mx` range.
- `fanctld` returns a fan to Auto when the app that set it quits, crashes or disconnects,
  and returns all fans to Auto at startup and on SIGTERM (including uninstall).
- If firmware drops a fan back to Auto (e.g. after sleep), `fanctld` re-applies it.

## Status

Verified on a MacBookPro16,1 running macOS 26: sensor reading, and manual fan control
through the helper (`F<n>Md` = 1 plus `F<n>Tg`; fan 0 reached a 3000 rpm target in about
8 seconds and returned to Auto on `auto 0`).

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
