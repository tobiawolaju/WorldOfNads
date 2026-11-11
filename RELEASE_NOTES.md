# Release Notes

## Android beta — 2026-11-11

- **Artifact:** `Release/wons.apk` (~85 MB), plus `wons.apk.idsig`
- **Preset:** Godot `Android` (release, signed with the project release keystore)
- **Target:** the live servers (`worldofnads.onrender.com`, room server `wons-room-server.onrender.com`)

### What's included

- Native Android client that boots, signs in and plays on device.
- Persisted WON login: the app reopens on the dashboard until you log out; the in-match name is your WON username.
- Dashboard matching the web build: real owned/equipped skins, match cards, level pill, right-edge backdrop fade.
- 3D preview orbit like the web (vertical + horizontal, no zoom).
- Chicken status in the event feed (`<user> is holding the chicken`, `<user> wins in 59s`, `30s`, `5s`, ...) instead of the old progress bar.
- Touch scrolling in the dashboard carousels, joystick auto-hide 0.5s after release.
- Weapon feel pass: per-weapon muzzle FX, tracers, shake and phone haptics.
- Eye shader is `unshaded`, so eyeballs stay flat white in any lighting.

### Install

1. Download `Release/wons.apk` on the Android device.
2. Allow "install unknown apps" for the browser/file manager when prompted.
3. Open the APK, install, then sign in with the same WON account used on web.

### Known issues

- Camera can clip through the floor when stepping down from elevated map parts.
- Dashboard player counts show `0` when the match payload has no count fields.
- Native skin minting needs the backend wallet key + a skin with `onChainId > 0`; failures print a code and detail in the log.

### Notes

`Release/` is ignored by git except for the files committed here, so re-exports do not silently re-add the APK. Build artifacts are published per release; the source of truth stays in `godot/`.
