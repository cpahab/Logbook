# Effective Arrival Time — VS Code Implementation Prompt

## Problem

The app currently shows the **last raw GPX fix timestamp** as the trip end time
when no end stop is detected. This is wrong whenever the track continues logging
after the boat has berthed:

| File           | App shows   | Correct arrival | Error   |
|----------------|-------------|-----------------|---------|
| 26 Sep 2024    | 21:58 UTC   | 13:24 UTC       | +8.5 h  |
| 06 Jun 2026    | 21:39 UTC   | 19:09 UTC       | +2.5 h  |
| 28 Jun 2026    | 23:43 UTC   | 16:00 UTC       | +7.7 h  |
| 28 Sep 2024    | 21:58 UTC   | 14:19 UTC       | +7.7 h  |

When an end stop IS detected (02/15/16/17 May, 18 Apr) the existing display is
already correct — the end stop's start time is used.

---

## Root cause

No end stop is detected on four trips because the GPS scatter at the end
location is too wide (> `max_stop_spread_m = 30 m`). This can be caused by a
wide anchor swing, GPS multipath in a marina, or degraded signal quality.
In every case the boat genuinely did stop; the pipeline correctly refuses to
place a fabricated end stop, but the fallback (last raw fix) is wrong.

---

## Solution: effective arrival from `win_speed`

Use the **windowed speed** (`win_speed_kn` on each `GpxFix`) rather than
instantaneous speed or the raw track end. The windowed speed is a 5-fix centred
average (±2 fixes = ~2 minutes), which filters out brief speed spikes and the
late excursions that would fool a backward scan of `inst_speed`.

**Algorithm:**

```
function effectiveArrivalFix(fixes, stops, underwayThreshold = 0.5):
    n = fixes.length

    // Find where to start searching — after the departure berth,
    // but always at least n/4 into the track so we don't catch
    // the start stop's own exit on short trips.
    startStopEnd = max index of any fix in a 'start' or 'mid' stop, or 0
    searchFrom = max(startStopEnd + 1, n / 4)

    // Scan forward and remember the LAST fix where win_speed > threshold
    lastMovingIdx = null
    for i from searchFrom to n-1:
        if fixes[i].winSpeedKn > underwayThreshold:
            lastMovingIdx = i

    // The fix immediately after the last moving fix = moment of arrival
    if lastMovingIdx != null and lastMovingIdx + 1 < n:
        return fixes[lastMovingIdx + 1]

    // Fallback: track ends while still moving (open sea, log cut short)
    return fixes[n - 1]
```

**Why `win_speed` not `inst_speed`:**
- `inst_speed` can spike briefly (a wave, a fender bump, GPS jitter) after the
  boat has berthed, causing a backward scan to report a time well after arrival.
  Example: 26 Sep has `inst_speed > 0.5 kn` at 19:34 UTC due to a late
  oscillation; `win_speed` correctly gives 13:24 UTC (= 15:24 local CEST).
- `win_speed` is already computed by the pipeline and stored on every `GpxFix`.
  No new computation needed.

**Why search from `max(startStopEnd, n/4)` not from the track midpoint:**
- Some trips (03 May, 06 Jun) start under way with no start stop. Using a
  fixed midpoint would miss them on short trips.
- Using `n/4` always skips the initial departure portion regardless of whether
  there is a start stop.

---

## What to show in the UI

Two cases:

**Case A — end stop detected** (spread ≤ 30 m, duration ≥ 5 min):
- Show `endStop.startTime` as arrival time. *(already correct — no change needed)*
- Show the berth marker with CEP50/R95 rings on the map.
- No indicator needed.

**Case B — no end stop detected** (wide spread or GPS degraded):
- Show `effectiveArrivalFix.time` as arrival time.
- Do **not** show a berth marker or error rings (there is no reliable position).
- Show a small indicator on the arrival time: a subtle icon (e.g. `~` prefix or
  a signal-quality icon) meaning "GPS position uncertain at arrival".
- Tooltip / detail view: "Arrival time estimated from last motion. GPS position
  quality was insufficient to determine exact berth location."

**Do not** show the raw track end time in either case.

---

## Affected code locations

| What                            | Where to change                               |
|---------------------------------|-----------------------------------------------|
| `TripResult` / stats model      | Add `effectiveArrivalTime: DateTime`          |
| `TripResult` / stats model      | Add `endPositionReliable: bool`               |
| GPX processing service          | Compute `effectiveArrivalFix` after pipeline  |
| Trip list / trip detail display | Use `effectiveArrivalTime` for "arrived at"   |
| Map display                     | Show berth marker only if `endPositionReliable` |
| Trip duration calculation       | Use `effectiveArrivalTime − effectiveDepartureTime` |

For the departure time (already discussed): use the first fix after the start
stop where `winSpeedKn > underwayThreshold`. The same `winSpeedKn` signal,
applied symmetrically.

---

## Validation table

After implementing, verify these times against the reference pipeline:

| File              | End stop? | Expected arrival (UTC) | Expected `endPositionReliable` |
|-------------------|-----------|------------------------|-------------------------------|
| 02_May_2026       | yes       | 13:31                  | true                          |
| 03_May_2026       | no        | 14:04 (last fix)       | false                         |
| 06_Jun_2026       | no        | 19:09                  | false                         |
| 15_May_2026       | yes       | 13:45                  | true                          |
| 16_May_2026       | yes       | 16:11                  | true                          |
| 17_May_2026       | yes       | 13:44                  | true                          |
| 18_Apr_2026       | yes       | 15:12                  | true                          |
| 26_Sep_2024       | no        | 13:24 (= 15:24 CEST)  | false                         |
| 28_Jun_2026       | no        | 16:00                  | false                         |
| 28_Sep_2024_1     | no        | 14:19                  | false                         |

---

## Reference implementation (Python)

In `gpx_filter_reference_v6.py`, the algorithm above is expressed as:

```python
UNDERWAY_KN = 0.5   # same as StatsSettings.underway_threshold_kn

def effective_arrival(fixes, stops):
    n = len(fixes)
    start_stop_end = max(
        (s.end_idx for s in stops if s.kind in ('start', 'mid')),
        default=0
    )
    search_from = max(start_stop_end + 1, n // 4)
    last_idx = None
    for i in range(search_from, n):
        if fixes[i].win_speed_kn > UNDERWAY_KN:
            last_idx = i
    if last_idx is not None and last_idx + 1 < n:
        return fixes[last_idx + 1]   # first fix of the stationary period
    return fixes[n - 1]              # still moving at track end
```

The `win_speed_kn` field is populated by `compute_speeds()` before this
function is called — no additional pipeline step required.
