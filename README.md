# Vesper

A private iPhone app that films your track day through Meta glasses and turns it into a
short, cinematic film: aperture title sequence, gauges in the style of a V12 grand tourer,
slow-motion on your best corners, the engine's own sound, and a soundtrack cut to the beat.

Two modes:

- **Track day**: lap timing, fastest lap, V-max, hardest braking.
- **Grand tour**: for spirited drives on the open road. The film is built from your best bends and pulls plus the scenery along the way, with trip distance and time in place of lap times. It doesn't brag about top speed, and the speedometer can be switched off for these films. Traffic lights won't end the recording; it waits until you've been parked 5 minutes.

It's built to be hands-free. You arm it in the paddock, and from then on you never touch it:

- **Recording starts and stops by itself.** Filming begins once you hold speed and ends after you've been parked for 45 seconds.
- **The glasses talk to you.** A British voice calls out each lap time and your fastest laps through the glasses' speakers.
- **Speed and revs in your eye-line.** On Meta Ray-Ban Display glasses, the in-lens screen shows live speed and RPM, with your lap and best lap underneath. When you cross the line, your lap time and gap to your best flash up for six seconds.
- **CarPlay.** The car's screen shows status and lap times, with Arm and End buttons that only work while you're stopped.
- **The phone can stay in your pocket.** The glasses stream compressed video that keeps recording with the phone locked.

> Track use only. Vesper is designed so you never need to look at the phone, but you're responsible for driving safely.

## How it works

| Piece | What it does |
| --- | --- |
| `Glasses/GlassesManager` | Meta Wearables Device Access Toolkit 1.0: pairing, the device session, the 720×1280 @ 30 fps HEVC camera stream. |
| `Glasses/FrameRecorder` | Writes the glasses' HEVC frames straight to `.mp4` without re-encoding. |
| `Glasses/LensDisplay` | The Ray-Ban Display's in-lens screen. |
| `Telemetry/TelemetryRecorder` | GPS and motion. G-forces come from yaw rate times speed, so the phone can be mounted at any angle or loose in a pocket. |
| `Telemetry/EngineAudio` | Records the cabin through the phone mic and reads **RPM from the engine note** (a V12 fires 6 times per revolution). |
| `Mission/MissionController` | Runs the drive end to end: arm, auto-record, live lap timing, voice call-outs, save. |
| `Edit/HighlightComposer` + `FilmOverlay` | Builds the film with AVFoundation and draws the overlay frame by frame. |
| `CarPlay/CarPlaySceneDelegate` | The CarPlay driving-task screen. |
| `Packages/VesperCore` | Platform-free logic with unit tests: lap detection, auto start line, auto-record, g-force maths, RPM pitch tracking, moment detection and beat-synced cut planning. |

### What goes in the film

Vesper scores every moment of the drive and keeps the best ones that fit the length you pick (30 s to 3 min):

- the biggest **lateral g** corners, with the top three in half-speed slow motion
- the hardest **braking** zones
- **V-max**, your highest speed
- the **fastest lap**, crossing the line
- a **launch**, if there is one

Clip lengths snap to the music's beat (124 BPM for the built-in theme) so cuts land on the drums.
The film opens with a run of dots and a gold aperture that opens onto your footage, and it closes on
"*CALLSIGN* WILL RETURN" with your stats.

## Your logo and music

The look is an homage: racing green, silver and gold, Didot type, counter-rotating tach. No
trademarked names, logos or music are bundled. For your own personal copy you can add your own:

- **On the phone:** Settings → *Your logo and soundtrack*.
- **At build time:** drop `logo.png` and/or `music.m4a` into `App/Vesper/Resources/Custom/`.

Without your own music, films use `vesper_theme.m4a`, an original cue synthesised by
`scripts/make_theme.py`.

## Build and install

You need a Mac with Xcode 16 or newer, an Apple developer account (free works for 7-day installs;
paid for longer), and your glasses set up in the Meta AI app.

1. `brew install xcodegen`, then run `xcodegen generate` in this folder and open `Vesper.xcodeproj`.
2. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and set `DEVELOPMENT_TEAM`.
3. In the Meta AI app, turn on **Developer Mode** for your glasses (Settings → your glasses → Developer Mode). With Developer Mode, the placeholder Meta app ID works. To skip Developer Mode, register Vesper in the [Wearables Developer Center](https://wearables.developer.meta.com/) and put its App ID and Client Token in `Secrets.xcconfig`.
4. Plug in your iPhone, pick it as the run destination and press Run.
5. In Vesper, tap **Pair**. The Meta AI app opens to approve the connection.

### When Vesper shows on the glasses

Vesper isn't the glasses' default app. It only puts itself on the lens while it's open on your iPhone, when you tap **Lens**, or when a drive is armed. Put it in the background and the glasses go back to normal; turning the glasses on doesn't bring Vesper up on its own.

### Hey Meta and voice commands

"Hey Meta, start Vesper" opens Vesper, then you talk to Vesper by name through the glasses' microphone: "Vesper, track day", "Vesper, grand tour", "Vesper, end mission", "Vesper, stand down", "Vesper, next car" or "Vesper, DB9". Phrases without "Vesper" are ignored. Both features are experimental in Meta's toolkit, so they're only for development and TestFlight builds. To turn them on:

1. In the [Wearables Developer Center](https://wearables.developer.meta.com/), open Vesper's app and switch on **Voice Invocation** (set the spoken name to "Vesper") and **Speech**.
2. In Vesper, go to Settings → Hey Meta and tap **Allow the glasses microphone**. The Meta AI app opens to approve it.

Apps built on Meta's toolkit can't go on the App Store yet, so install Vesper directly from Xcode or through TestFlight.

### TestFlight (no Mac needed)

`.github/workflows/testflight.yml` builds Vesper on GitHub and uploads it to TestFlight on every push to `main` (or from the Actions tab). One-time setup, which needs a paid Apple Developer Program membership:

1. In [App Store Connect](https://appstoreconnect.apple.com/apps), create a new iOS app with bundle ID `com.aseeras.vesper` (register the ID under Certificates, Identifiers & Profiles first if it isn't offered).
2. Under Users and Access → Integrations → App Store Connect API, create a key with the **Admin** role (it needs to manage cloud signing certificates). Download the `.p8` file and note the Key ID and Issuer ID.
3. In this repo's Settings → Secrets and variables → Actions, add `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` (paste the whole `.p8` file).
4. Run the TestFlight workflow. When the build has processed, add yourself as an internal tester and install it from the TestFlight app.

Internal TestFlight builds skip Apple's beta review, which matters because Meta's toolkit isn't App Store-approved yet.

### CarPlay

CarPlay uses Apple's **CarPlay Driving Task** entitlement, which has been granted for this
team, so `Config/Base.xcconfig` points `VESPER_ENTITLEMENTS` at
`App/Vesper/Resources/Vesper-CarPlay.entitlements`. To build on a team without it, set
`VESPER_ENTITLEMENTS = App/Vesper/Resources/Vesper.entitlements` in `Secrets.xcconfig`.

## Tuning

Settings has the knobs that matter for a DB9: 12 cylinders and a 6,800 rpm redline for the tach,
the speed that starts recording, how long to wait after parking, units, voice call-outs, the lens
display, and **glasses delay**. If the gauges in a film run ahead of the picture, raise the delay
a little.

## Tests

```sh
cd Packages/VesperCore && swift test
```

CI runs those tests and a full simulator build of the app on every pull request.
