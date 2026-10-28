# Pixel 9 Pro XL debloat

One click applies the battery settings and package disables used on a Pixel 9 Pro XL. A package that is not installed is skipped. The script keeps going.

## Run

USB debugging has to be on. Unlock the phone and allow this computer.

On Windows, double-click `debloat.bat`. It looks for `adb.exe` on `PATH`, in Android SDK platform-tools, and in `Downloads\platform-tools-latest-windows\platform-tools`.

From WSL or Linux:

```bash
chmod +x debloat.sh restore.sh
./debloat.sh
```

Undo it with `restore.bat` or `./restore.sh`.

Running it again is safe.

## What it changes

Screen timeout 30 seconds, Wi-Fi and Bluetooth scanning off, mobile data not kept alive on Wi-Fi, Adaptive Charging and Adaptive Connectivity on, animations at 0.5x.

These packages are disabled when present:

| App | Package |
|---|---|
| Chrome | `com.android.chrome` |
| Google TV | `com.google.android.videos` |
| Meet | `com.google.android.apps.tachyon` |
| YouTube Music | `com.google.android.apps.youtube.music` |
| Digital Wellbeing | `com.google.android.apps.wellbeing` |
| Recorder | `com.google.android.apps.recorder` |
| Pixel Tips | `com.google.android.apps.tips` |
| Markup | `com.google.android.markup` |
| ARCore | `com.google.ar.core` |
| Android System Intelligence | `com.google.android.as` |
| Private Compute Services | `com.google.android.as.oss` |
| Now Playing | `com.google.android.apps.pixel.nowplaying` |
| Safety Core | `com.google.android.safetycore` |
| Pixel Stand and its updater | `com.google.android.apps.dreamliner`, `com.google.android.dreamlinerupdater` |
| CBRS network monitor | `com.google.android.apps.cbrsnetworkmonitor` |
| AI wallpapers, emoji wallpapers | `com.google.android.apps.aiwallpapers`, `com.google.android.apps.emojiwallpaper` |
| System Tracing, MusicFX, Easter egg | `com.android.traceur`, `com.android.musicfx`, `com.android.egg` |
| Print recommendations, bookmarks, feedback, partner setup, diagnostics, restore | see `disable-packages.txt` |

Use another browser before disabling Chrome. YouTube stays installed. Android System Intelligence off means Now Playing, Live Caption, Live Translate, and on-device smart replies are off.

X (`com.twitter.android`) and Amazon (`com.amazon.mShop.android.shopping`) stay installed. Background work and notifications are turned off. Remove either line from `restrict-packages.txt` if you want that app's notifications.

Android Auto is force-stopped, not disabled. It starts again when a car connects.

Phone, Messages, Maps, Photos, Wallet, Play Services, the launcher, and YouTube are left alone.
