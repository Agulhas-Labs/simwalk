# SegmenterFixture

A sailing log on fixed data ("Logbook": tabs Log, Passages and Boat), the subject app behind the
accessibility trees the segmenter tests read: `Tests/SimWalkCoreTests/Fixtures/segmenter-*.json`, loaded by
`AXSegmenterTests`, `BundleDiffTests` and `DegenerateChartRuleTests`. Each fixture is one capture's
`ax-tree.json` from a walk of `segmenter.walkbook.json`, unedited. `project.yml` says what each screen is for.

## How the fixtures were made

Simulator: iPhone 18 Pro (`iPhone19,2`), iOS 27.0 (24A434), Xcode 27.0 (27A266a). From the repository root,
with the simulator booted:

```sh
xcodebuild -project Fixtures/SegmenterFixture/SegmenterFixture.xcodeproj -scheme SegmenterFixture \
  -destination 'id=<udid>' -derivedDataPath .build/segmenter-dd build
xcrun simctl install <udid> .build/segmenter-dd/Build/Products/Debug-iphonesimulator/SegmenterFixture.app
simwalk walk Fixtures/SegmenterFixture/segmenter.walkbook.json --output .build/segmenter.simwalk --device <udid>
```

Then each capture is copied to its fixture name, compacted to one line with `jq -c`:

```sh
copy() { jq -c . ".build/segmenter.simwalk/screens/$1/ax-tree.json" > "Tests/SimWalkCoreTests/Fixtures/segmenter-$2.json"; }
copy summary/light                                       summary-light
copy summary/dark-dt_uictcontentsizecategoryaccessibilityl summary-dark-axl
copy passages/light                                      passages-first-week
copy passages/light-args_bd3d4257                        passages-later-week
copy passage_detail/light                                passage-detail
copy wind/light                                          wind-detail
copy hours_afloat/light                                  hours-afloat-detail
copy anchor_watch/light                                  anchor-watch-detail
```

| Fixture | Walkbook screen | State | Route |
| --- | --- | --- | --- |
| `segmenter-summary-light` | `summary` | light | tab `Log` |
| `segmenter-summary-dark-axl` | `summary` | dark, `UICTContentSizeCategoryAccessibilityL` | tab `Log` |
| `segmenter-passages-first-week` | `passages` | light | tab `Passages` |
| `segmenter-passages-later-week` | `passages` | light, launched with `-SegmenterFixtureLaterWeek` | tab `Passages` |
| `segmenter-passage-detail` | `passage-detail` | light | tab `Passages`, tap `Coastal passage` |
| `segmenter-wind-detail` | `wind` | light | tab `Boat`, tap `Wind` |
| `segmenter-hours-afloat-detail` | `hours-afloat` | light | tab `Boat`, tap `Hours afloat` |
| `segmenter-anchor-watch-detail` | `anchor-watch` | light | tab `Boat`, tap `Anchor watch` |

## What varies between walks

Nothing the tests read. Two walks of the same build give the same trees but for one thing: the tab bar's
three image elements sometimes carry their SF Symbol name (`book.closed`, `sailboat`,
`gauge.with.dots.needle.33percent`) as an `identifier` and sometimes carry none, from one capture to the
next. The segmenter keys the tab bar by its role and reads only labels, so the fixtures are committed as
captured, with or without them.

## Two things to know when reading the trees

- On iOS 27, every screen inside a `NavigationStack` (all but `Log`) holds an element of type
  `Toolbar`, labelled `Toolbar` and covering the whole screen, though nothing is in a toolbar. The
  segmenter reads it as a bar, so those screens' keys end `toolbar`, `tab bar`. Neither hiding the bottom
  bar nor a UIKit navigation controller in place of the stack removes it.
- Each chart is hidden from accessibility, so the tree holds only its row of axis labels, 2 pt under the
  room the chart takes. The Boat speed chart on the passage detail is drawn at no height, which leaves its
  axis row 14 pt under its header row: the degenerate chart the tests flag.
