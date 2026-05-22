# Juliana micro-optimizations profiling

## Environment

- Branch: `SergioCastano`
- Device used: `emulator-5554`, Medium Phone API 36.1
- Requested device was Pixel 6 API 33, but that AVD was not available locally.
- Package: `com.example.spendant_flutter`
- Scenario: open and close New Expense screen 5 times from Home.

## Commits

- `5111524` - `perf: add const constructors to style objects in new_expense_screen`
- `172fef2` - `perf: replace ListView with ListView.builder in set_goal_screen`

## gfxinfo

Flutter/Impeller reported 0 HWUI frames in both runs. This matches the note in
the assignment: Flutter may bypass the HWUI frame counters, so these values are
not a reliable performance source for this run.

| Metric | Before | After |
| --- | ---: | ---: |
| Total frames rendered | 0 | 0 |
| Janky frames | 0 (0.00%) | 0 (0.00%) |
| 50th percentile | 4950ms | 4950ms |
| 90th percentile | 4950ms | 4950ms |
| 99th percentile | 4950ms | 4950ms |
| Number Slow UI thread | 0 | 0 |
| Number Slow issue draw commands | 0 | 0 |

## meminfo snapshot

| Metric | Before | After |
| --- | ---: | ---: |
| TOTAL PSS | 183159 kB | 190101 kB |
| TOTAL RSS | 241872 kB | 272744 kB |
| Java Heap PSS | 15320 kB | 11568 kB |
| Native Heap PSS | 14748 kB | 34668 kB |
| Graphics PSS | 0 kB | 0 kB |

These are whole-process snapshots and include app startup, Firebase, geolocation,
Google Play Services, and emulator noise. They are useful as artifacts, but they
do not isolate the micro-allocation change as cleanly as DevTools Memory would.

## DevTools

The VM Service URLs were:

- BEFORE: `http://127.0.0.1:31336/tfQwAxOcpz4=/devtools/?uri=ws://127.0.0.1:31336/tfQwAxOcpz4=/ws`
- AFTER: `http://127.0.0.1:18657/qUYV6sQCPqg=/devtools/?uri=ws://127.0.0.1:18657/qUYV6sQCPqg=/ws`

The DevTools Performance and Memory screenshots/CSV require browser interaction
for recording and exporting. They were not captured automatically in this run.

## Code impact

- `new_expense_screen.dart`: fixed style objects now use const constructors or
  const parent style objects. Dynamic values such as `formBottomPadding`,
  `bottomPadding`, `selected`, and `withValues(...)` remain non-const.
- `set_goal_screen.dart`: the goals list is now rendered through
  `ListView.builder`, so the scrollable asks for items by index instead of
  eagerly passing a full children list to `ListView`.
