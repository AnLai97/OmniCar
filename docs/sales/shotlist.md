# OmniCar – shot list

Nothing here is recorded yet. Record on a real car (or head unit on the bench), not the HTML preview in `tools/preview`.

## Before recording

- [ ] Release build (`OMC_AUTOTEST=0`), so no dev test bar shows on the car screen.
- [ ] Settings language set to English for the international set; record a Vietnamese set later if needed.
- [ ] No conflict / rescue cards on the OmniCar page.
- [ ] Car parked. Any shot with video playing on the car screen must clearly be parked (handbrake / P visible or no driver).
- [ ] Clean phone: full battery icon, no personal notifications, neutral wallpaper; Do Not Disturb on.
- [ ] Car screen shots: photograph the head unit straight on (tripod, no glare) or capture from the car if the unit allows. Note the head unit model and resolution (the "Car screen" section of a Send log report) for each shot.
- [ ] Only show apps you are allowed to show; avoid DRM apps (they show black) and copyrighted video – use your own clip or a public-domain one in YouTube.

## The 6 screenshots

| # | Title (EN / VI) | What is on screen | Notes |
|---|---|---|---|
| 1 | Three apps, one screen / Ba app trên một màn | Car screen, Split Screen 1 large + 2: Maps (large), music app, Vietmap Live or a second CarPlay app | Hero shot. Divider knob visible. |
| 2 | YouTube on CarPlay / YouTube trên CarPlay | Car screen, 2 panes: Maps on one side, YouTube (via App Bridge) playing on the other | Parked. Own or public-domain video. |
| 3 | Any iPhone app / Mọi app iPhone | CarPlay home screen with iPhone app icons (YouTube, TikTok…) next to the normal CarPlay apps | Shows App Bridge icons on the home screen. |
| 4 | Speed and limit at a glance / Tốc độ và biển giới hạn | Car screen with the Speed Bubble over a map, showing speed and a posted-limit sign | Needs Vietmap Live or GOFA running with GPS; a real road with a limit. |
| 5 | Your own startup video / Video khởi động của bạn | Car screen mid-playback of a custom Startup Screen video right after connecting | Pick a frame that reads well as a still (logo or car). |
| 6 | Everything in one place / Tất cả trong một nơi | iPhone: Settings > OmniCar main page (header card, feature list) | Phone screenshot, not the car. |

Export: car shots at the head unit's native resolution plus a 16:9 crop; phone shot at native resolution. Keep originals in a `docs/sales/media/` folder (TODO: decide whether media goes in git).

## 60-second video storyboard

Format: 16:9, 1080p or higher, 30 fps. No voice-over needed; short on-screen captions (EN, VI subtitle track optional). Calm background music, licensed.

| Time | Shot | Caption |
|---|---|---|
| 0:00–0:04 | Car parked, phone plugged in (or wireless connects). Startup Screen video plays on the car screen, tap to skip. | OmniCar – Unlock every limit of CarPlay |
| 0:04–0:10 | CarPlay home screen; open the layout tray, pick 2 panes: Maps + music. | Split Screen: two CarPlay apps side by side |
| 0:10–0:16 | Switch to 3 panes, then 1 large + 2. Drag the divider knob to resize. | Two or three apps, drag to resize |
| 0:16–0:20 | Swap two panes; pop one app into the floating window. | Swap panes, floating window |
| 0:20–0:30 | Tap a YouTube icon on the CarPlay home screen; it opens in a pane via App Bridge, then goes full screen. (Parked.) | App Bridge: iPhone apps on the car screen – no CarBridge needed |
| 0:30–0:34 | TikTok or another iPhone app in a pane next to Maps. | Any iPhone app, in a pane or full screen |
| 0:34–0:44 | Driving footage (passenger-held camera or dash mount): Speed Bubble on the map showing speed and the limit sign; speed passes the limit and the bubble changes. | Speed Bubble: your speed and the limit, from Vietmap Live / GOFA |
| 0:44–0:50 | iPhone: Settings > OmniCar, scroll the feature list, open Speed Bubble styles briefly. | Every feature has its own switch |
| 0:50–0:55 | iPhone: Support section; tap Send log to show the share sheet. | One-tap log for support |
| 0:55–1:00 | Car screen with the hero split layout; OmniCar logo and repo / store link. | OmniCar · iOS 15–16 · rootless · `<TODO: store URL>` |

Rules while filming:
- No video playing on the car screen in any driving shot (0:34–0:44 shows only the map and bubble).
- Do not show the Siri / `omnicar://` Shortcuts feature unless it has been recorded working.
- Do not show iOS 17 / 18 or roothide in the video; they are not tested.
