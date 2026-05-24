# Esteban micro-optimizations — `budget_screen.dart`

## Environment

- Branch: `feat/esteban-microopts` (based on `SergioCastano`)
- Target file: `lib/src/screens/budget_screen.dart`
- Scenario: open Budget screen and scroll the incomes list.

## Commits

- `daf7dba` — `perf: replace ListView with ListView.builder in budget_screen`
- `449879a` — `perf: wrap each _IncomeCard in a RepaintBoundary in budget_screen`

## Code changes

### Opt 1 — `ListView` → `ListView.builder`

The incomes list was previously built with `ListView(children:[...])`, which
instantiates every `_IncomeCard` eagerly regardless of viewport visibility.
The new implementation:

- Keeps the regular `ListView` for the empty-state path (single placeholder
  card, lazy build would be wasteful).
- Switches to `ListView.builder` for the non-empty case, so cards are built
  on demand as they enter the viewport.

PDF reference: Avoid building widgets off-screen / use lazy list builders.

### Opt 2 — `RepaintBoundary` per `_IncomeCard`

Each `_IncomeCard` is now wrapped in a `RepaintBoundary` inside the
`itemBuilder`. The card's repaint layer is isolated from the rest of the
list, so scroll, hover or per-card state changes do not invalidate the
neighbouring cards.

> The `INSTRUCTIONS.md` originally suggested wrapping a chart with
> `RepaintBoundary`. `budget_screen.dart` does not render a chart — it only
> renders a scrollable list of incomes. The optimization was adapted to the
> element that actually repaints during scroll: each income card.

PDF reference: Isolate repaint layers around widgets that change
independently from their surroundings.

## Profiling

**Pending.** The code changes are merged in the two commits listed above.
Empirical BEFORE/AFTER profiling with Flutter DevTools (Performance + Memory
tabs) has not yet been captured for this entry and will be added in a
follow-up commit before the final delivery.

Expected metrics to record once profiling is run:

| Source | Metric |
| --- | --- |
| DevTools Performance | UI thread frame times, raster thread frame times, jank frames |
| DevTools Memory | `_IncomeCard` instance count (Total vs New Space) |
| Console (`flutter run --profile`) | Logged frame times during the scroll scenario |

Notes for whoever runs the profiling:

- iOS Simulator does not support profile mode; use macOS desktop
  (`flutter run --profile -d macos`) or a physical iOS device.
- `dumpsys gfxinfo` is not applicable on macOS/iOS targets and is unreliable
  on Flutter Android targets (Skia/Impeller bypasses HWUI), as already
  documented by Juliana in `profiling/juliana/RESULTS.md`.
- Same scrollable scenario as described above (open Budget, scroll incomes
  list for ~10 s) for both BEFORE and AFTER runs.
