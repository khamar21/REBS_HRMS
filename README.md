# REBS HRMS: Offline-Capable Employee Workspace

A Flutter app (Android/iOS target, tested on Android) that lets one preconfigured employee view attendance, check in and out with GPS validation, and apply for leave. The app stays usable offline and synchronises attendance events reliably, without ever creating duplicate server records.

The backend is a local mock HTTP API (Node/Express) with repeatable failure scenarios.

---

## Contents

1. [Quick start for reviewers](#1-quick-start-for-reviewers)
2. [Features](#2-features)
3. [Architecture](#3-architecture)
4. [Offline sync design](#4-offline-sync-design-the-main-challenge)
5. [Location and geofence](#5-location-and-geofence)
6. [Mock API and scenarios](#6-mock-api-and-scenarios)
7. [What a production server must re-validate](#7-what-a-production-server-must-re-validate)
8. [Technology choices](#8-technology-choices)
9. [Tests](#9-tests)
10. [Assumptions](#10-assumptions)
11. [Known limitations and trade-offs](#11-known-limitations-and-trade-offs)
12. [Time spent](#12-time-spent)
13. [AI usage disclosure](#13-ai-usage-disclosure)

---

## 1. Quick start for reviewers

### Option A: Install the APK (fastest)

1. Install `app-debug.apk` on an Android phone (allow "install unknown apps" if asked).
2. The APK was built to talk to the mock API at the URL below.
   - Hosted API: `<ADD HOSTED URL HERE, or delete this line if not hosted>`
   - If the API is on a free host it may sleep when idle. Open the URL once in a browser and wait up to a minute before testing.
3. In the app, open the **Demo office location** card on the Home screen and tap **Use my location**. This moves the office to where you are standing, so check-in works from anywhere (see [section 5](#5-location-and-geofence)).

### Option B: Run everything locally

**Requirements:** Flutter 3.x (Dart 3), Node.js 18+, an Android emulator or phone.

**1. Start the mock API**

```bash
cd mock_api
npm install
npm start
```

You should see `Mock API on :3000`. Leave this terminal open.

Optional: set the office location the server reports.

```powershell
# PowerShell
$env:OFFICE_LAT="11.02981"; $env:OFFICE_LNG="76.26145"; npm start
```

```bash
# macOS / Linux
OFFICE_LAT=11.02981 OFFICE_LNG=76.26145 npm start
```

**2. Run the app**

```bash
cd rebs_hrms
flutter pub get
flutter run
```

The default API address is `http://10.0.2.2:3000`, which is how the Android **emulator** reaches your computer's `localhost`.

**Using a physical phone instead of an emulator?** `10.0.2.2` will not work. Use one of these:

```bash
# USB cable: forward the phone's port 3000 to your computer
adb reverse tcp:3000 tcp:3000
flutter run --dart-define=BASE_URL=http://localhost:3000

# Same Wi-Fi: use your computer's LAN IP (find it with ipconfig / ifconfig)
flutter run --dart-define=BASE_URL=http://192.168.1.6:3000
```

If the phone browser cannot open `http://<LAN-IP>:3000/employee/me`, allow port 3000 through your firewall.

**3. Build an installable debug APK**

```bash
flutter build apk --debug --dart-define=BASE_URL=https://your-api.example.com
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

### Resetting between demos

```bash
curl -X POST http://localhost:3000/__reset     # clears server-side data
```

Also clear the app's local data (Android: App info, Storage, Clear data) so the local cache and pending events match the reset server.

---

## 2. Features

### Dashboard
- Employee name, ID, department
- Today's status: Not Checked In, Checked In, Checked Out
- Check-in time, check-out time, live elapsed working duration
- Leave balance (casual and sick)
- Latest five attendance records, each with a Pending Sync / Synced / Rejected chip
- Loading, empty, error and offline states; pull to refresh

### Attendance
- One check-in per company day; check-out only after check-in
- Double taps cannot create duplicates (button disabled while busy, a repository-level busy guard, and the rules also look at pending events)
- Timestamp and GPS coordinates captured per event
- 200 m geofence with a message showing the actual distance when outside
- Handles: location services off, permission denied, permission permanently denied (with an **Open settings** action), and location unavailable
- Configurable office coordinates and company timezone

### Offline storage and sync
- Dashboard, attendance history, balance and leave requests are cached in SQLite
- Valid check-in/out is saved locally when offline and shown as **Pending Sync**
- Pending events survive app restart
- Manual **Sync Now** button (header and banner)
- Automatic sync when connectivity returns and on app start
- Strict ordering, idempotent retries, rejection handling (see section 4)

### Leave
- Form: type (Casual/Sick), start date, end date, reason
- Local validation: start not before the company date, end not before start, reason of at least 10 non-whitespace characters, days not above balance, no overlap with Pending/Approved requests
- Server validation errors are shown even when local validation passes
- Requests list with Pending / Approved / Rejected chips
- Submission requires connectivity; previously loaded requests remain viewable offline

### UI
- Material 3 with a glassmorphism look (frosted cards over a gradient background)
- Scrollable layouts that adapt to different screen sizes

---

## 3. Architecture

Layer-first structure. Dependencies only point inward: `presentation` uses `data` and `domain`; `data` uses `domain`; `domain` imports nothing from Flutter, HTTP or storage.

```
lib/
├── main.dart
├── core/                 config, theme, company clock
│   ├── config.dart           dart-define settings (BASE_URL, SCENARIO, office override)
│   ├── theme.dart            colours, theme, GlassBackground, AppCard, StatusChip
│   └── company_clock.dart    company timezone, company date, time formatting
├── domain/               pure Dart business rules (no Flutter, no HTTP)
│   ├── models.dart           AttendanceEvent, Employee, LeaveRequest, enums
│   ├── attendance_rules.dart status, check-in/out rules, Haversine geofence
│   ├── leave_rules.dart      leave validation
│   └── records.dart          DayRecord, DashboardData, LeaveData
├── data/                 API access and local persistence
│   ├── api_client.dart       Dio client, scenario header, outcome classification
│   ├── db.dart               SQLite: attendance_events queue + JSON cache
│   ├── location_service.dart geolocator wrapper with typed failures
│   └── repository.dart       online-first loading with cache fallback; record(); leave
├── sync/
│   └── sync_engine.dart      ordered, idempotent event synchronisation
└── presentation/
    ├── providers.dart        Riverpod notifiers (dashboard, leave)
    ├── screens/              home, leave, shell (navigation)
    └── widgets/              office card

mock_api/
└── server.js             Express mock API with failure scenarios
```

**Where the rules live:** all business rules (check-in/out, geofence, leave validation) are in `domain/`, and widgets only call notifiers. No business logic sits in `build` methods.

**Data flow on a check-in tap**

```
HomeScreen -> DashboardNotifier.act()
  -> Repository.record()      validate rules, get GPS, check geofence,
                              save event locally as Pending (UUID created here)
  -> SyncEngine.sync()        send pending events in order
  -> refresh()                UI shows Pending / Synced / Rejected
```

---

## 4. Offline sync design (the main challenge)

### Event identity and idempotency

Every attendance action gets a **UUID v4 `eventId` generated on the device at tap time**, before any network call, and stored with the event. That same id is sent on **every** retry.

The server stores each processed `eventId` with its result. If it receives an id it has already processed, it returns the original result (HTTP 200) instead of creating a second record. The local table also has a `UNIQUE` constraint on `event_id`.

This makes retries safe even when the client does not know whether the first attempt succeeded.

### Outcome classification

`ApiClient.submitEvent` maps every result to exactly one of three outcomes:

| Server result | Outcome | What the client does |
|---|---|---|
| 200 / 201 | **synced** | Mark Synced, continue to the next event |
| 4xx (for example 409 attendance exists, 422 no check-in) | **rejected** | Mark Rejected with the server's reason, never retry, continue to the next event |
| Timeout, no connection, 5xx | **transient** (outcome unknown) | Stop the queue. The event stays Pending and is retried later with the same `eventId` |

### Timeout where the server may have accepted the event

A timeout is treated as **unknown, not failed**. The event stays Pending. On the next sync it is sent again with the same `eventId`. If the server had already saved it, the server answers 200 with the stored result and the client marks it Synced. No duplicate is created.

The mock's `timeout` scenario reproduces exactly this: it saves the event, then never replies.

### Ordering

Events are stored in a local table with an auto-increment `seq`. `SyncEngine` always processes pending events in `seq` order. On a transient failure it **stops**, so a later check-out is never sent before an earlier check-in that is still unresolved.

If a check-in is permanently rejected, the following check-out is still sent, and the server rejects it (for example `NO_CHECK_IN`), so it ends up Rejected with a clear reason.

### Other sync behaviour
- Only one sync runs at a time. A loop picks up events added while a sync was running.
- Sync is triggered by: a successful local save, the **Sync Now** buttons, connectivity returning, and app start (for events left from a previous session).
- Pending events live in SQLite, so they survive the app being closed and reopened.
- Rejected events do not block new attempts: the attendance rules ignore rejected events.

### Duplicate prevention (three layers)
1. UI: the button is disabled while an action is running.
2. Repository: a busy guard, plus rules evaluated against synced **and** pending events.
3. Server: idempotent `eventId`, plus one attendance record per date.

---

## 5. Location and geofence

The device captures GPS coordinates and the app computes the distance to the office using the Haversine formula. Attendance is allowed within **200 m** (radius is configurable on the server).

### Where the office coordinates come from

Highest priority wins:

| Priority | Source | Typical use |
|---|---|---|
| 1 | **Demo override**: the **Use my location** button on the Home screen | Reviewers who are not near the office |
| 2 | `--dart-define=OFFICE_LAT=... --dart-define=OFFICE_LNG=...` | Developers |
| 3 | `GET /employee/me` from the server (`OFFICE_LAT`, `OFFICE_LNG` environment variables, with defaults in `server.js`) | Default configuration |

### How reviewers can simulate locations

- **Easiest:** tap **Use my location** on the Demo office card, then check in. Tap **Reset** to go back to the configured office. Checking in again while away from the office shows the "You are N m from the office" message.
- **Android emulator:** `... (Extended controls) > Location`, enter coordinates, and set them to the office, or move far away to test the outside-area message.
- **Command line:** `flutter run --dart-define=OFFICE_LAT=<lat> --dart-define=OFFICE_LNG=<lng>`.

The demo override exists for review convenience. A production app would use only the office configured by the server.

### Location failures handled
- Location services disabled
- Permission denied
- Permission permanently denied (the snackbar offers **Settings**)
- Position unavailable or timed out (10 s limit)

---

## 6. Mock API and scenarios

### Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/employee/me` | Employee and office configuration |
| GET | `/attendance?month=YYYY-MM` | Attendance history for a month |
| POST | `/attendance/events` | Submit a check-in or check-out event (idempotent by `eventId`) |
| GET | `/leave/balance` | Leave balance |
| GET | `/leave/requests` | Leave requests |
| POST | `/leave/requests` | Submit a leave application |
| POST | `/__reset` | Reset in-memory data (review helper) |
| GET | `/` | Health check |

**Contract notes**

- `POST /attendance/events` body: `eventId`, `type` (`check_in` or `check_out`), `timestamp` (UTC ISO-8601), `date` (company-local `YYYY-MM-DD`), `lat`, `lng`.
- Responses: `201` new event, `200` already-processed `eventId` (idempotent replay), `409` duplicate attendance, `422` rule violation (for example no check-in), `400` malformed.
- Addition to the suggested contract: the client sends the company-local `date` and an `eventId`, so the server can enforce one record per day and idempotency.

### Scenarios

The app sends an `x-scenario` header. Switch it with the **flask icon** in the app's header, or start the app with `--dart-define=SCENARIO=timeout`.

| Scenario | Behaviour |
|---|---|
| `success` | Normal responses |
| `slow` | Every response is delayed by 5 seconds |
| `timeout` | The server **saves** the attendance event, then never responds, so the client times out. The retry with the same `eventId` returns the stored result |
| `error500` | Every request returns HTTP 500 |
| `duplicate` | Check-in is rejected with 409 `ATTENDANCE_EXISTS` |
| `leave_reject` | Leave submission is rejected with 422 `LEAVE_REJECTED` |

Natural server-side leave validation also applies: insufficient balance and overlapping dates return 422.

### Demo walkthrough of the offline flow

1. Check in with `success` (Synced).
2. Switch to `timeout` and check out: it shows **Pending Sync**.
3. Close and reopen the app: still **Pending Sync**.
4. Switch to `success` and tap **Sync Now**: it becomes **Synced**, with one server record.

---

## 7. What a production server must re-validate

Device-side validation improves the user experience but can be bypassed (modified app, rooted device, spoofed GPS, changed device clock, replayed requests). A production server must **not trust the client** and must repeat these checks:

**Identity and access**
- Authenticate every request, and derive the employee from the token, never from the request body
- Authorise that the employee may submit attendance and leave only for themselves

**Idempotency and integrity**
- Enforce `eventId` uniqueness scoped to the employee, and return the original result for a replay
- Enforce one attendance record per employee per company date with a **database unique constraint**, so races between two devices cannot create duplicates
- Enforce that check-out requires an existing check-in, and that check-out is not after another check-out
- Validate ordering and state transitions on the server (the client's order is only a request)

**Time**
- Record the server's receive time; treat the device timestamp as a claim and reject or flag timestamps too far from server time (clock skew limits), or in the future
- Compute the company date on the server from the configured timezone, and do not trust the client's `date` field
- Check for events submitted long after they were created, and apply a late-sync policy

**Location**
- Recompute the distance between the submitted coordinates and the office on the server, using server-side office configuration
- Use reported accuracy, and detect mock-location flags or implausible jumps where the platform allows

**Leave**
- Recompute the day count, balance (inside a transaction, to prevent double spending), overlap with Pending/Approved requests, date ranges and reason length
- Apply policy rules (notice periods, holidays, weekends) that the client does not know

**Operational**
- Rate limiting and request size limits
- Input validation and consistent error codes
- Audit logging of accepted and rejected events

---

## 8. Technology choices

| Concern | Choice | Why |
|---|---|---|
| State management | **Riverpod** (`flutter_riverpod`) | Compile-safe dependency injection with simple async states for loading/error/data. Providers can be overridden with fakes in tests, so no mocking framework is needed in widgets. Less boilerplate than BLoC for an app of this size |
| HTTP | `dio` | Per-request timeouts, interceptors (scenario header), and clear separation of connection errors from HTTP status codes |
| Local storage | **`sqflite`** | `sqflite` was chosen instead of Drift to avoid code generation for this small schema and to keep the build simple. Plain SQL is enough for one event queue table and a JSON cache table |
| Connectivity | `connectivity_plus` | Triggers a sync attempt when the network returns. Connectivity is only a hint; the real signal is whether the request succeeds |
| Location | `geolocator` | Permission handling and position with timeouts |
| Identifiers | `uuid` | UUID v4 event ids for idempotency |
| Time zones | `timezone`, `intl` | Company-local date and formatting independent of the device's timezone |
| Tests | `flutter_test`, `mocktail`, `sqflite_common_ffi` | In-memory SQLite for persistence tests |

**Storage design:** `attendance_events` is a real table (it needs ordering, status and uniqueness). Server data (employee, monthly attendance, balance, leave requests) is stored as JSON blobs in a `cache` table, because it is only ever read back whole.

---

## 9. Tests

```bash
cd rebs_hrms
flutter test
```

Coverage targets:

| Requirement | Test file |
|---|---|
| Check-out without check-in is rejected | `test/attendance_rules_test.dart` |
| Repeated submission or retry does not create duplicate attendance | `test/sync_engine_test.dart` |
| Pending attendance survives persistence and syncs in order | `test/sync_engine_test.dart` |
| Overlapping leave dates are rejected | `test/leave_rules_test.dart` |
| Widget test for a loading, error or pending-sync state | `test/dashboard_widget_test.dart` |

`<UPDATE BEFORE SUBMITTING: run flutter test, then state the result here, for example "All N tests pass", or list which tests are not yet written.>`

---

## 10. Assumptions

- One preconfigured employee (`EMP001`); login is out of scope
- One attendance session per day; no overnight shifts
- The company timezone comes from the server (`Asia/Kolkata` in the mock)
- All calendar days count as leave days (weekends and holidays are ignored)
- Leave submission needs connectivity; only attendance is queued offline
- The mock API keeps data in memory and resets when restarted
- The device needs to be online at least once so the employee profile (and office configuration) is cached before the first offline check-in
- Plain HTTP is allowed for the local mock API (`usesCleartextTraffic`); a real deployment would use HTTPS only

---

## 11. Known limitations and trade-offs

- **No background sync.** Sync runs only while the app is open, as the assignment allows.
- **The mock does not decrement leave balance** when a request is submitted, so the balance stays constant. Overlap and balance checks still work against the request itself.
- **The dashboard is online-first.** If the server is unreachable (including a 5xx), the app shows cached data with the offline banner; it does not distinguish "no network" from "server down" in the UI.
- **Attendance history window:** the current and previous month are fetched and cached; older months are not.
- **Elapsed duration** while checked in uses the device clock; it is only a display value, and the server timestamp is the record.
- **A rejected check-in is not rolled back into its dependent check-out.** The check-out is sent anyway and rejected by the server. This is simple and correct, but the user sees two Rejected messages.
- **Device clock and GPS can be spoofed.** This is why the server must repeat the checks in section 7.
- **Free hosting may sleep**, adding a delay to the first request.
- **Only Android was run and tested.** iOS needs the location usage strings in `Info.plist`, and the code is not Android-specific.
- **The "Use my location" card is a review aid**, not production behaviour.
- **Debug APK only**, not signed or optimised for release.
- `<ADD ANY FEATURE YOU DID NOT FINISH HERE>`

---

## 12. Time spent

`<FILL IN HONESTLY. Example below; replace with your real numbers.>`

| Area | Time |
|---|---|
| Mock API and setup | ... |
| Data layer (models, SQLite, API client) | ... |
| Attendance, location and sync engine | ... |
| Dashboard and leave UI | ... |
| Tests | ... |
| README, APK, demo video | ... |
| **Total** | **... h** |

---

## 13. AI usage disclosure

`<EDIT TO MATCH WHAT YOU ACTUALLY USED.>`

I used AI assistants (Claude by Anthropic, and GitHub Copilot) during this assignment for: planning the architecture, drafting code (the sync engine, repository, rules, screens, mock API) and documentation, and debugging build and analyzer errors.

I reviewed and ran the generated code on a device and can explain and modify every part of it, including the event identity and idempotency design, the sync ordering rules, the outcome classification, and the offline caching strategy.