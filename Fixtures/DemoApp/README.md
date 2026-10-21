# DemoApp

A generic "Account" screen (a list of rows, each a title and a value) that SimWalk's README demo walks twice: once
as shipped, once with a layout regression switched on. `project.yml` says how the project is made.

## The baseline

Each row is the standard adaptive row: an `HStack` (title, spacer, value) at ordinary text sizes and, at an
accessibility size, a `VStack` with the title above the value. A plain `HStack` would wrap the value at an
accessibility size until its top sat above the title, so VoiceOver would read the value first and `bundle audit`
would report `readingOrder` on the baseline itself; a demo baseline has to be clean.

## The regression

With the `SimWalkDemoRegression` user default on, each row stops being the adaptive row and becomes a `ZStack` with the title pinned leading and the value pinned trailing, both at full width. At the
default size, light or dark, the two texts do not touch; at an accessibility text size they draw over each other.
Both stay separate `StaticText` runs, so `bundle diff` flags an `overlap` with a crop and `bundle audit` reports
`largeTypeOverflow`, in the accessibility-size state only. At that size the diff also raises `box` and `row template`
flags; those are genuine, because the adaptive row became a different layout.

The switch is a user default rather than a state `arguments` entry because a state's arguments go into its slug,
and `bundle diff` pairs states by exact slug: the baseline and the regression walk run the **same** walkbook.
`-SimWalkDemoRegression YES` still works for a single launch.

## The truncation specimen

With the `SimWalkDemoTruncation` user default on, each row's title is a single line (`lineLimit(1)`) in a fixed
150-point width, with the value below it. At the default size the titles fit whole; at
`UICTContentSizeCategoryAccessibilityXL` they end in an ellipsis. It exists to check whether Apple's accessibility
audit (`walk --apple-audit`) reports truncated text. Switch it on the way the regression is switched on:
`xcrun simctl spawn <udid> defaults write dev.simwalk.demo SimWalkDemoTruncation -bool YES`, and delete the key
afterwards. The baseline and the regression are unchanged.

## Run it

The app is iPhone-only (`TARGETED_DEVICE_FAMILY "1"`), so lease an iPhone simulator explicitly: a plain
`simwalk lease acquire` can pick an iPad, where the app runs in compatibility mode and the walks fail. Any iPhone
simulator works; `iPhone 17` is an example name. A name reaches only a shut-down device: if that iPhone is booted,
pass its UDID (`--device <udid>`), or `--clone-from <udid>` for a fresh copy that `lease release` deletes. From the
repository root (`lease acquire` prints `udid:` and `token:`):

```sh
simwalk lease acquire --device "iPhone 17"
xcodebuild -project Fixtures/DemoApp/DemoApp.xcodeproj -scheme DemoApp \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/demo-app build
APP=.build/demo-app/Build/Products/Debug-iphonesimulator/DemoApp.app

simwalk walk Fixtures/DemoApp/demo.walkbook.json --lease <token> --app-path $APP --output baseline.simwalk

xcrun simctl spawn <udid> defaults write dev.simwalk.demo SimWalkDemoRegression -bool YES
simwalk walk Fixtures/DemoApp/demo.walkbook.json --lease <token> --app-path $APP --output regression.simwalk
xcrun simctl spawn <udid> defaults delete dev.simwalk.demo SimWalkDemoRegression

simwalk bundle diff baseline.simwalk regression.simwalk --crops crops   # exit 2: overlap flags, crops/*.png
simwalk bundle audit regression.simwalk                                 # largeTypeOverflow, five rows
simwalk bundle audit baseline.simwalk                                   # no largeTypeOverflow, no readingOrder

simwalk lease release <token>
```

`defaults write` through `simctl spawn` reaches the app's preferences, and each walk reinstalls and relaunches the
app, so the default holds for the whole walk. Check the result by the regression bundle's accessibility-size
screenshot, not by the command.

The states are light, dark, `UICTContentSizeCategoryAccessibilityXL` and Arabic right to left. The walkbook's one
step scrolls to the first row (`row-title-0`, on screen in every state, so it never swipes) only because a walkbook needs a non-empty route.
