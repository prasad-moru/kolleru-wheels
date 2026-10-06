# Kolleru Wheels (కొల్లేరు వీల్స్)

Technical architecture, product rationale, implementation boundaries, and delivery roadmap.

**Architecture snapshot:** 6 October 2026. **Primary platform:** Flutter Android. **Current milestone:** locally persisted prototype with implemented Phases 1–4; backend distribution and field deployment remain planned.

## 1. Executive summary

Kolleru Wheels is a hyper-local, zero-commission transport directory and urgent-load bulletin board for the Kolleru Lake corridor and the Godavari–Krishna delta belt. Its initial directory covers Kaikaluru, Mandavalli, Kalidindi, and Akividu, including lake-bed and surrounding villages such as Pulaparru, Kovvadalanka, Penumakalanka, and Kolletikota.

The product addresses a practical discovery problem: commercial transport contacts sit in fragmented phone diaries; dispatch can depend on local middlemen and their cuts; vehicles return empty after deliveries; and owners must maintain utilization while meeting vehicle-finance EMI commitments. These are product hypotheses and design inputs, to be validated during the on-ground pilot rather than presented as measured outcomes.

The solution is a bulletin-style directory that makes the right vehicle and driver easy to recognize, contact, and share. Farmers and merchants browse without logging in. Drivers register a local profile, update availability and their current spot, and export a digital visiting card for WhatsApp. Urgent loads remain discoverable for 30 minutes, with callers negotiating directly outside the app.

### Why a conventional ride-hailing model is a poor default

The anti-pattern is importing an Ola/Uber/Porter-style automatic dispatch model without validating its assumptions against rural freight conditions. This is a critique of that architectural pattern, not a claim about the capabilities of those services.

| Rural constraint | Why nearest-vehicle dispatch is insufficient | Kolleru Wheels response |
| --- | --- | --- |
| Canal bunds, lake edges, narrow approaches, and indirect crossings | Straight-line distance can misrepresent a usable approach or travel route. | Use recognizable village and mandal clusters; let the parties confirm access by phone. |
| Payload, bed length, rack, and material differences | A nearby compact vehicle can be unsuitable for long TMT rods, heavy cement loads, PVC pipes, or aqua cargo. | Show model, declared capacity, specialization tags, and distinguishable silhouettes. |
| Local trust and intermittent connectivity | Automated allocation and mandatory account creation can add friction to existing phone and WhatsApp relationships. | Zero-login browsing, direct dialer handoff, offline directory data, and shareable cards. |
| Empty return trips and EMI pressure | A passenger-trip abstraction does not directly express backhauls or owner utilization needs. | Expose availability and urgent needs; plan return-trip tagging. |

The app does not promise a booking, a particular response time, verified vehicle suitability, or a guaranteed load. Its role is discovery and contact.

## 2. Target personas and UX primitives

### Persona 1: Truck owner / driver — డ్రైవర్ / యజమాని

The owner-driver needs more paid utilization, fewer empty return journeys, and a simple way to announce availability. A useful profile conveys the vehicle, capacity, specialization, base village, current spot, and contact number. The digital visiting card provides a high-status regional identity that can be placed on WhatsApp Status or forwarded to merchants.

Primary journey: Driver Mode → register once on the phone → dashboard → availability/current-spot update → view or share card → inspect urgent loads → call the shipper.

### Persona 2: Hardware / input merchant — ఆర్డర్ ఇచ్చే వ్యాపారి

The merchant is a high-volume proxy dispatcher for customers buying TMT iron rods, cement bags, PVC pipes, and aqua feed. Vehicle selection must account for cargo geometry and weight, not simply whether a truck is nearby. The merchant benefits from visual vehicle selection, capacity and specialization labels, and a quick urgent-load post when a known driver is busy.

Primary journey: choose a village and vehicle → compare available drivers → call → alternatively post a pickup, destination, material, and contact number.

### Persona 3: Farmer / rural shipper — రైతు / గ్రామస్తుడు

The intended farmer persona can be text-constrained while remaining tech-fluent through WhatsApp audio, YouTube, and UPI sound cues. Limited comfort with long text is not equivalent to limited digital ability. This persona relies on recognizable vehicle silhouettes, color plus explicit status text, short Telugu/English labels, and one-tap access to the dialer. Audio familiarity informs the design; UPI and payment audio are not app integrations.

Primary journey: recognize the appropriate vehicle → choose the locality → call a driver or post an urgent need with minimal typing.

### Shared UX principles

- **Zero-login browsing:** `HomeDirectoryScreen` is the launch screen. Driver Mode is optional. Local registration is not authenticated login or phone verification.
- **Visual recognition:** offline `CustomPainter` illustrations distinguish Bolero Pickup, Tata Ace, Dost, Eicher 14 ft, and Tractor. Model and capacity labels remain visible.
- **Outdoor contrast:** primary green `#00875A`, warning amber `#FFC107`, deep charcoal `#202B28`, and dashboard busy red `#D9383A`. Status always includes text and/or an icon rather than relying on color alone.
- **Large touch targets:** shared button themes provide 56–60 logical-pixel minimum heights; prominent call, registration, posting, and sharing actions use 64-pixel minimum heights. Vehicle badges appear at 88–120 pixels in major screens.
- **Bilingual copy:** centralized strings pair Telugu and English. UTF-8 source files preserve Telugu characters. Current localization is embedded bilingual copy, not a language-switching localization framework.
- **Offline first launch:** static villages, seeded drivers, local profiles, vector badges, and system-font Telugu fallback do not require asset downloads. Google Fonts is installed but not used by the current theme.
- **Direct contact:** `url_launcher` receives a `tel:` URI and delegates calling to the platform dialer. A dialer failure produces a recoverable message. Demo numbers display a notice instead of launching a call.
- **Accessibility:** layouts adapt to narrow screens and larger text. `AudioCueButton` uses Flutter semantic announcements when supported; spoken output depends on an enabled screen reader such as TalkBack. It is not standalone text-to-speech or a recorded-audio system.

## 3. Architecture overview and decisions

The project uses a lightweight layered architecture: shared constants/theme and matching utilities under `core`, models and storage under `data`, and screens/widgets under `presentation`. It follows separation-of-responsibility principles while deliberately avoiding unnecessary framework complexity at this milestone.

It is not yet a strict domain-isolated Clean Architecture implementation. Presentation imports repositories directly, `ProximityMatcher` consumes a data model, and the directory contract currently lives beside the mock implementation. Introducing a separate domain layer and backend-facing interfaces is a planned evolution when remote synchronization is implemented.

```mermaid
flowchart TD
    App[KolleruWheelsApp] --> Home[HomeDirectoryScreen]
    Home --> Match[ProximityMatcher]
    Home --> Mock[MockDirectoryRepository]
    Home --> Mode[DriverModeScreen]
    Mode --> Registration[DriverRegistrationScreen]
    Mode --> Dashboard[DriverDashboardScreen]
    Registration --> Profile[LocalDriverRepository]
    Dashboard --> Profile
    Home --> Profile
    Home --> Post[PostLoadBottomSheet]
    Post --> Loads[LoadRequestRepository]
    Dashboard --> Board[LoadPoolBoard]
    Board --> Loads
    Profile --> Preferences[SharedPreferences]
    Loads --> Preferences
    Home --> Card[VisitingCardScreen]
    Dashboard --> Card
    Card --> Export[PNG file and native share sheet]
```

### Architectural decision register

| Decision | Reason | Consequence / boundary |
| --- | --- | --- |
| Bulletin and direct-contact model | Preserve familiar local negotiation and minimize transaction complexity. | No fares, commissions, automatic bookings, payment workflow, or allocation guarantee. |
| Static village IDs and mandal membership | Deterministic offline grouping and durable references. | Cluster definitions need pilot validation and versioned migration if IDs change. |
| Separate persisted and display driver models | Persist structured fields while reusing existing cards. | `LocalDriverProfile.toDriverModel()` is the display adapter. |
| `StatefulWidget` and `setState` for screen state | Keep small workflows explicit without adding a state-management dependency. | Repositories own storage; screens own loading, error, and operation states. |
| `ChangeNotifier` for the local load pool | Farmer and driver views need immediate updates after successful writes. | The default singleton is shared within this app process, not across devices. |
| SharedPreferences JSON storage | Small, easily testable local records with no backend prerequisite. | No transactional database, encrypted vault, authenticated identity, or synchronization. |
| Serialized storage operations | Avoid overlapping read-modify-write operations losing state. | Driver writes serialize across repository instances in one isolate; load writes serialize within one repository instance. |
| Stable three-tier matching | Make grouping predictable and explainable. | No GPS, road-distance routing, or learned ranking; order within a tier follows repository order. |
| `CustomPainter` vehicle badges | Offline, crisp, high-contrast silhouettes without image downloads. | Illustrations communicate vehicle classes, not verified manufacturer specifications. |
| Rasterize a self-contained visiting card | Produce an image that works in existing social-sharing workflows. | The user chooses the destination in the native share sheet. |
| Clock injection and explicit TTL | Make exact expiry behavior testable. | Current production timestamps depend on the device clock; server authority is deferred. |

## 4. Complete folder tree and component roles

The following tree lists every current application Dart source and test file. Platform and generated directories are represented at their root; their generated contents are not application architecture modules.

```text
kolleru-wheels/
├── ARCHITECTURE.md
├── README.md
├── pubspec.yaml
├── pubspec.lock
├── analysis_options.yaml
├── .gitignore
├── .metadata
├── kolleru_wheels.iml
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── constants/
│   │   │   ├── app_colors.dart
│   │   │   ├── app_strings.dart
│   │   │   ├── driver_spots.dart
│   │   │   └── villages.dart
│   │   ├── theme/
│   │   │   └── app_theme.dart
│   │   └── utils/
│   │       └── proximity_matcher.dart
│   ├── data/
│   │   ├── models/
│   │   │   ├── driver_model.dart
│   │   │   ├── load_request.dart
│   │   │   ├── load_request_model.dart
│   │   │   ├── local_driver_profile.dart
│   │   │   └── vehicle_type.dart
│   │   └── repositories/
│   │       ├── load_request_repository.dart
│   │       ├── local_driver_repository.dart
│   │       └── mock_directory_repository.dart
│   └── presentation/
│       ├── common/
│       │   ├── audio_cue_button.dart
│       │   ├── call_button.dart
│       │   ├── vehicle_badge.dart
│       │   └── village_picker.dart
│       ├── driver/
│       │   ├── driver_dashboard_screen.dart
│       │   ├── driver_mode_screen.dart
│       │   ├── driver_registration_screen.dart
│       │   ├── load_pool_board.dart
│       │   └── visiting_card_screen.dart
│       └── farmer/
│           ├── home_directory_screen.dart
│           └── post_load_bottom_sheet.dart
├── test/
│   ├── driver_onboarding_test.dart
│   ├── load_request_test.dart
│   ├── proximity_matcher_test.dart
│   ├── visiting_card_test.dart
│   └── widget_test.dart
├── android/                      # Primary deployment platform
├── ios/                          # Flutter platform scaffold
├── linux/                        # Flutter platform scaffold
├── macos/                        # Flutter platform scaffold
├── web/                          # Flutter platform scaffold
├── windows/                      # Flutter platform scaffold
├── .git/                         # Version-control metadata
├── .idea/                        # Local IDE metadata
├── .dart_tool/                   # Generated tooling state
├── .flutter-plugins-dependencies # Generated plugin metadata
└── build/                        # Generated builds and optional test previews
```

### Core modules

| File | Responsibility |
| --- | --- |
| `lib/main.dart` | Runs `KolleruWheelsApp`, sets the app title and accessible theme, disables the debug banner, and opens the farmer directory. |
| `core/constants/app_colors.dart` | Defines shared outdoor colors and the dashboard busy state. |
| `core/constants/app_strings.dart` | Centralizes bilingual labels, validation/error copy, proximity headings, specialization/material choices, and sharing text. Some dynamic labels remain in widgets. |
| `core/constants/villages.dart` | Defines `Village`, `Mandal`, immutable static clusters, a flattened list, and ID lookup through `KolleruVillages.find()`. |
| `core/constants/driver_spots.dart` | Associates display spot labels with village IDs, including Kaikaluru Adda and Akividu Market, plus ordinary village locations. |
| `core/theme/app_theme.dart` | Configures Material 3, contrast, typography, form decoration, and large filled/outlined button styles using system fonts. |
| `core/utils/proximity_matcher.dart` | Defines `ProximityTier`, `ProximityMatch`, village-to-mandal lookup, tier classification, deduplication, and deterministic ranking. |

### Data modules

| File | Responsibility |
| --- | --- |
| `data/models/vehicle_type.dart` | Enum for `boleroPickup`, `tataAce`, `dost`, `eicher14ft`, and `tractor`, with bilingual display labels. Enum names are stored as stable identifiers. |
| `data/models/driver_model.dart` | Directory/card projection: ID, name, phone, base village, current-spot label and optional village ID, vehicle type, display capacity, availability, demo flag, vehicle number, and specializations. |
| `data/models/local_driver_profile.dart` | Structured persistent driver profile with numeric capacity in tons, base/current villages, spot label, JSON serialization/validation, immutable specialization list, selective `copyWith()`, and conversion to `DriverModel`. |
| `data/models/load_request_model.dart` | Active urgent-load contract with open/closed status, serialization, destination validation, and the exact 30-minute lifetime predicate. |
| `data/models/load_request.dart` | Earlier scaffold model containing origin/destination `Village` objects and basic contact/material fields. Retained in the tree but unused by the urgent-load workflow; do not confuse it with `LoadRequestModel`. Consolidation is future cleanup. |
| `data/repositories/mock_directory_repository.dart` | Declares `DirectoryRepository` and implements immutable seeded driver retrieval with optional filters. Six demo records span Pulaparru, Kaikaluru Town, and Kovvadalanka; four are available, two busy, and all five vehicle classes appear. Numbers and plates are placeholders. |
| `data/repositories/local_driver_repository.dart` | Saves/reads/updates one registered profile in SharedPreferences; serializes writes, validates profile identity for full updates, and offers availability/current-spot field updates. |
| `data/repositories/load_request_repository.dart` | Lazily restores a local load list, caches it in memory, serializes operations, creates/closes requests, filters active loads, sorts newest first, and notifies listeners after successful persistence. |

### Presentation modules

| File | Responsibility |
| --- | --- |
| `presentation/common/vehicle_badge.dart` | Draws five distinctive offline vehicle silhouettes: Bolero rack/TMT rods; Tata Ace snub cab and compact bed; Dost broad bumper and medium cargo body; tall Eicher cab/railing; tractor bonnet, large rear wheel, and trailer. |
| `presentation/common/call_button.dart` | Shared large green contact control, repeated-tap protection during launch, dialer-error handling, and demo-record notice. |
| `presentation/common/audio_cue_button.dart` | Screen-reader announcements plus visible guidance; no standalone audio playback dependency. |
| `presentation/common/village_picker.dart` | Reusable base-village form dropdown with mandal context and required-selection validation. |
| `presentation/farmer/home_directory_screen.dart` | Zero-login entry point; saved village selection, visual vehicle filters, availability filter, proximity sections, demo plus locally registered drivers, direct call controls, visiting-card navigation, Driver Mode drawer/action, and urgent-load launcher. |
| `presentation/farmer/post_load_bottom_sheet.dart` | Keyboard-aware bilingual form for pickup, destination, material, optional vehicle requirement/name, shipper phone, validation, and asynchronous posting. |
| `presentation/driver/driver_mode_screen.dart` | Resolves the persisted profile once per visit, showing registration if absent, dashboard if present, or a retry screen on storage/decode failure. |
| `presentation/driver/driver_registration_screen.dart` | Collects identity/contact, registration number, capacity, visual vehicle selection, village, and specialization chips; persists before dashboard transition. |
| `presentation/driver/driver_dashboard_screen.dart` | Shows the registered driver, large availability switch, editable current spot, digital-card access, Farmer View navigation, and `LoadPoolBoard`. |
| `presentation/driver/load_pool_board.dart` | Observes repository changes and app resume; shows route/material/elapsed time/call cards, empty/error/loading states, and schedules refreshes around minute boundaries and expiry. |
| `presentation/driver/visiting_card_screen.dart` | Contains the opaque `TransportVisitingCard`, contact and share actions, `RepaintBoundary` capture, temporary PNG lifecycle, native sharing, and error recovery. |

### Geographic directory inventory

There are **26 village/locality entries in four directory clusters**:

| Mandal cluster | Entries |
| --- | --- |
| Kaikaluru | Kaikaluru Town, Kovvadalanka, Gudivakalanka, Atapaka, Bhujabalapatnam, Pallevada, Kolletikota, Alapadu, Singarayapalem |
| Mandavalli | Mandavalli, Chintapadu, Pulaparru, Penumakalanka, Prathikollalanka, Lokamudi, Ingilipakalanka |
| Kalidindi | Kalidindi, Sanrudraram, Guraja, Korukollu, Pothumarru |
| Akividu | Akividu Town, Dumpagadapa, Taratava, Ajjamuru, Kolleru border hamlets |

These are the supplied product directory clusters, not a certified administrative boundary dataset. “Kolleru border hamlets” is a catch-all locality, not one official village. Validate spellings, Telugu names, cluster membership, hub labels, and accessible road connections with local participants before publishing geographic claims.

### Dependency inventory

| Package / constraint | Current role |
| --- | --- |
| Flutter SDK; Dart `^3.13.5` | Widgets, Material UI, painting, image capture, semantics, and app lifecycle. |
| `url_launcher: ^6.2.5` | Opens `tel:` contact URIs. |
| `shared_preferences: ^2.2.3` | Local profile, selected village, and urgent-load JSON records. |
| `share_plus: ^10.1.2` | `Share.shareXFiles()` native image-sharing handoff. |
| `path_provider: ^2.1.5` | App temporary directory for exported visiting-card images. |
| `google_fonts: ^6.2.1` | Installed for potential typography work; unused by the current offline system-font theme. |
| `flutter_svg: ^2.0.10+1` | Installed for potential SVG assets; current badges use `CustomPainter`. |
| `cupertino_icons: ^1.0.8` | Retained starter dependency; main UI uses Material icons. |
| `flutter_test` and `flutter_lints: ^6.0.0` | Unit/widget verification and static-analysis rules. |

Caret constraints are declared requirements, not exact resolved versions. `pubspec.lock` records the dependency versions used by this application build. Native platform registrants are generated by Flutter.

## 5. Data contracts, persistence, and state ownership

### SharedPreferences records

| Key | Encoding | Owner |
| --- | --- | --- |
| `directory_village_id` | Village ID string; removed for “All villages”. | `HomeDirectoryScreen` |
| `registered_driver_profile_v1` | One JSON object with `schemaVersion: 1`. | `LocalDriverRepository` |
| `urgent_load_requests_v1` | JSON array of urgent-load records. | `LoadRequestRepository` |

**Registered driver fields:** `id`, `name`, `phone`, `baseVillage`, `currentSpotVillage`, `currentSpotLabel`, `vehicleType`, `capacityTons`, `specializations`, `vehicleNumber`, and `isAvailable`. Village objects are serialized as village IDs. The label allows a hub such as Kaikaluru Adda to retain its identity while ranking against `kaikaluru-town`.

**Urgent-load fields:** `id`, `posterName`, `posterPhone`, `fromLocation`, `toVillageId`, `materialType`, nullable `vehicleTypeNeeded`, `createdAt`, and `status` (`open`/`closed`). `createdAt` is serialized as UTC ISO 8601. A null vehicle requirement means any vehicle. Pickup is a free-text spot, not a structured village or GPS coordinate.

Registration requires a name of at least two trimmed characters, a normalized Indian mobile number, a conventional vehicle-registration format, a selected village, and finite capacity greater than zero and at most 100 tons. These validations check input shape; they do not verify ownership, registration validity, road fitness, or permissible payload. Specializations are optional selections: iron rods, cement, live fish, and paddy.

Posting validates pickup, destination, and mobile number. A missing shipper name becomes “రైతు / Shipper”; material defaults to the first choice. Supported material chips are iron/rods, cement, pipes, fish feed, and miscellaneous goods.

### State and failure behavior

Screen-local state uses `setState`; asynchronous callbacks check whether their widget is still mounted. Operation flags suppress repeated submissions and simultaneous dashboard updates. The dashboard changes its displayed profile only after successful persistence; a failed availability update preserves the previous value and displays a retry message.

`LocalDriverRepository` uses a static write queue across its instances within the current isolate. Partial updates read the latest profile inside the queued operation. `LoadRequestRepository` serializes reads and writes per instance and publishes changes after committing the JSON record. The default shared instance is the application’s load-pool owner; independently constructed instances have independent caches and queues and are not a cross-instance consistency mechanism.

Malformed stored JSON is surfaced as an error rather than treated as a missing profile/pool or silently overwritten. Driver Mode and the board expose retry states. There is no recovery/export/delete-data UI yet. Local IDs support this prototype; backend identity and conflict-resolution policies remain to be designed.

## 6. Key technical workflows

### 6.1 Driver onboarding and dashboard navigation

1. The directory’s Driver Mode action/drawer entry opens `DriverModeScreen` without blocking farmer browsing.
2. `getProfile()` resolves the saved driver. A missing profile opens registration; a valid profile opens the dashboard. Read failures show a retry screen.
3. Registration initializes current spot to the base village and availability to true, normalizes contact data, and saves the complete profile before transitioning.
4. Within Driver Mode, the registration callback swaps the displayed screen without adding an extra route. A standalone registration screen can replace its route with the dashboard.
5. Availability calls `updateAvailability()`. The spot chooser calls `updateCurrentSpot()` with a village and optional hub label. Base village remains unchanged.
6. The current profile is adapted to `DriverModel` when opening the visiting card.
7. Farmer View opens the directory with the shared repositories. Its Driver Mode action returns to the dashboard. Returning to the original directory refreshes the local profile.

The current workflow manages one local driver profile on a phone. It does not create a remotely discoverable account or authenticate the entered phone number.

### 6.2 Three-tier proximity matching engine

`ProximityMatcher.rank(drivers, selectedVillageId)` assigns available drivers to the best qualifying tier:

| Priority | Tier | Predicate | Directory heading |
| --- | --- | --- | --- |
| 1 | Same village / Local | Current-spot village **or** base village equals the selected village. | మీ ఊరిలోనే ఉన్న వాహనాలు / Same village |
| 2 | Same mandal / Mandal hub | No Tier 1 match; current-spot village **or** base village belongs to the selected village’s mandal cluster. | మండల కేంద్రంలో అందుబాటులో ఉన్నవి / Same mandal cluster |
| 3 | Adjacent-mandal product concept / Delta belt | No higher-tier match; a known base/current village is in another supported Kolleru cluster. | పక్క మండలాల్లో వాహనాలు / Wider delta belt |

Current Tier 3 is a **wider-belt fallback**, not an explicit map of adjacent mandal boundaries. Tier 2 establishes same-cluster membership, not proof that a vehicle is parked at the mandal’s administrative center. Labels should be interpreted as discovery groupings; actual location is shown separately.

Classification uses stable village IDs. Free-text labels are not parsed to infer geographic location. Missing/unknown current IDs fall back to the base village. An unknown selected village yields no matches. Unavailable drivers are excluded from the matcher. IDs are deduplicated, and repository order is preserved within a tier. A moved driver can still be Tier 1 through its base village because that is the specified matching rule; the displayed current spot lets the caller confirm actual proximity.

When a village is selected, the directory retrieves vehicle-filtered candidates across the belt and renders the ranked available sections. Busy drivers appear in a separate section if “Available only” is off. Without a selected village, the ordinary directory view remains available. The locally registered profile is included alongside demo records.

Example: for **Kovvadalanka**, an available Kovvadalanka tractor is Tier 1; an available Kaikaluru Town truck is Tier 2; an available Pulaparru pickup is Tier 3. A busy Kovvadalanka vehicle is shown only in the separate busy section.

No vehicle is automatically assigned. Caller and driver must confirm access, capacity, rack compatibility, material suitability, current availability, and commercial terms.

### 6.3 Digital visiting-card PNG generation pipeline

```text
LocalDriverProfile.toDriverModel() or directory driver
  → TransportVisitingCard (opaque, self-contained card)
  → RepaintBoundary + GlobalKey
  → endOfFrame and RenderRepaintBoundary.toImage(pixelRatio)
  → ui.Image.toByteData(format: ui.ImageByteFormat.png)
  → path_provider.getTemporaryDirectory()/kolleru_cards/
  → PNG file + XFile(mimeType: image/png)
  → Share.shareXFiles()
  → native share sheet → user chooses WhatsApp → My Status
```

The exported card includes the “కొల్లేరు వీల్స్ / Kolleru Wheels” header/emblem, large driver name, vehicle silhouette/model, vehicle number, capacity, specialization badges, base village, current spot, availability, and contact banner. Demo records include a placeholder notice. Calling/sharing controls sit outside the boundary and are excluded from the image.

Capture waits for a rendered frame and checks the boundary is ready. Its scale targets 1080-pixel width, capped at 3× and approximately four million pixels to limit memory use on inexpensive phones. The PNG is written and flushed before sharing. The share operation passes a source rectangle for platform popover anchoring. Repeated share taps are blocked while the image is prepared, errors are surfaced, and the `ui.Image` is disposed in `finally`.

Only the app’s exported PNG files older than one day are cleaned during a subsequent export. Recent files remain available to the recipient app after the share sheet closes. This is opportunistic cleanup, not a guaranteed scheduled deletion service.

The accompanying text is: “నా కొల్లేరు వీల్స్ విజిటింగ్ కార్డ్. రవాణా అవసరాలకు సంప్రదించండి.” The image-share implementation does not force-open WhatsApp or automatically publish a Status. Posting remains the user’s action inside the recipient application.

### 6.4 Urgent-load creation and live pool

1. The farmer taps **అత్యవసర లోడ్ / Post Urgent Load** in the directory.
2. A keyboard-aware bottom sheet accepts a pickup spot or quick chip (“కైకలూరు మార్కెట్”, “దుకాణం వద్ద”), a destination village, material, optional required vehicle and name, and a shipper phone number. The selected directory village can prefill the destination.
3. Validation runs before `createRequest()`. A new request starts `open`, using the repository clock for creation time.
4. The repository retains currently active records plus the new record, writes JSON, updates its memory cache, and notifies subscribers only after the write succeeds.
5. The sheet closes on success and the directory shows confirmation. A failed write keeps the form available with an error.
6. `LoadPoolBoard` reads active requests newest first and displays route, material icon/type, requested vehicle when specified, shipper name, elapsed time, and a large Call Shipper button.

The default pool is shared by farmer and driver views **on this phone**. The board currently displays all active local requests; it does not filter pickup proximity or vehicle eligibility. Destination is structured but pickup is free text, so reliable pickup-based matching requires a future structured origin field. Entering a vehicle requirement informs the driver but does not automatically allocate or enforce a match.

### 6.5 Thirty-minute TTL and lifecycle

The active predicate is:

```text
status == open
AND createdAt <= now
AND now < createdAt + 30 minutes
```

A request is active at 29 minutes 59 seconds and expired at exactly 30 minutes. Closed and future-dated records are excluded. The clock is injectable for deterministic tests; production currently uses the device clock.

`getActiveRequests()` applies the predicate on every read and returns an immutable newest-first list. `closeRequest(id)` persists the closed state; an unknown ID is a no-op. Closing a request is a repository capability, not currently a farmer-facing completion button. Expiration is computed, not stored as a third status.

The board schedules a timer for the earliest of the next elapsed-minute label boundary or request expiry, rechecks on app resume, and filters again at build time. It cancels timers and unregisters listeners on disposal. A revision counter prevents older asynchronous refreshes from overwriting newer results. No permanent periodic timer runs when the pool is empty.

Expiration hides a record immediately when it is read/refreshed; it does **not** immediately delete its persisted bytes. Creating a new request prunes inactive entries from the stored list. Closing alone can retain older records. A production retention/erasure policy and server-authoritative timestamps belong to the backend/database roadmap.

## 7. Compliance and security boundaries

### Intermediary discovery scope

The intended product boundary is pure intermediary discovery: publish contact/profile information and short-lived load notices, then let the parties communicate directly. The current app does not set fares, calculate commissions, hold escrow, collect payments, integrate UPI transactions, broker an in-app contract, or guarantee fulfillment. These are explicit architectural exclusions and should be preserved when adding a backend.

This product boundary is not a regulatory classification or legal exemption. Avoiding transactional features and government-document collection reduces the data and operational scope; it does not eliminate all regulatory or PII responsibility.

### Data minimization

- Do not add Aadhaar or other government-ID numbers/images, driving-license scans, RC documents/scans, bank details, payment credentials, or identity-document upload fields to the current workflow.
- A vehicle registration **number** is collected for the visiting card; the RC document itself is not stored. Names, phone numbers, registration numbers, village/spot information, and load descriptions still require careful handling.
- Location is manually selected at village/hub level. There is no background GPS tracking, route history, or continuous driver surveillance.
- Demo records must remain visibly marked; their placeholder numbers must not be dialed or presented as verified participants.
- Shared images intentionally include contact details. The UI should make that disclosure clear; external recipients can retain or forward the image outside the app’s control.

### Platform and storage boundaries

`tel:` launching delegates contact to the dialer; the main Android manifest does not request `CALL_PHONE`. The app also does not request contacts, SMS, or location access in that manifest. The exact resolved plugin behavior and complete merged release manifest should be inspected before an APK is distributed.

SharedPreferences is local persistence, not an encrypted PII vault or an identity authority. No remote authentication, moderation, account ownership proof, server authorization, or notification subscription consent is implemented. Treat local validation as input validation only.

Before shared production publication, design explicit contact-publication consent, access rules, deletion and retention handling, abuse reporting, rate limits, and moderation. Keep phone numbers and full profiles out of diagnostic logs and notification payloads unless necessary and intentionally authorized. Do not place service credentials or server messaging keys in the APK.

## 8. Roadmap and progress matrix

“Completed” below refers to the implemented and tested local scope, not a production launch or measured field adoption.

| Phase | Status | Delivered / intended scope | Remaining exit criteria |
| --- | --- | --- | --- |
| Phase 1 — Scaffold & Static Village Directory | Completed | Layered folder structure, models, four clusters/26 localities, six demo drivers, bilingual theme and directory. | Validate locality spellings, memberships, and navigation with pilot users. |
| Phase 2 — Realistic Badges, Dialer CTA, WhatsApp PNG Exporter | Completed | Five painter badges, large contact controls, detailed visiting card, PNG capture and native sharing. | Verify dialer/share behavior, Telugu glyphs, and WhatsApp Status on target Android phones. |
| Phase 3 — Driver Registration, Persistence, Availability Toggle | Completed | One local profile, form validation, saved availability/spot, returning-driver routing, Farmer View integration. | Define remote identity, profile editing/deletion, consent, and sync behavior for backend publication. |
| Phase 4 — 3-Tier Proximity Engine & Urgent Load Pool | Completed locally / In progress for production | Available-driver tier sections, urgent posting, persisted shared local pool, 30-minute expiry, live local refresh and calls. | Validate adjacency/access assumptions; implement cross-device distribution, authoritative expiry, moderation, and structured origin matching. |
| Phase 5 — Free-tier Backend & FCM Broadcast | Planned | Evaluate a low-cost/free-tier-capable backend; shared directory/load storage; controlled mandal topic notifications. | Choose provider using current quotas and projected usage; implement authorization, timestamps, TTL filtering, consent, retries, and monitoring. No provider or cost guarantee is committed. |
| Phase 6 — APK Generation & On-Ground Pilot | Planned | Release signing/build, installation, and field trials across merchants, owners, and farmers. | Verify release configuration, permissions, physical-device behavior, outdoor readability, weak connectivity, route access, and user comprehension. |

The latest code verification preceding this document passed `flutter analyze` with no issues and `flutter test` with **28 passing tests**. That result validates the tested local behavior, not cross-device load delivery, actual WhatsApp publication, or field performance.

## 9. Future optimizations and production evolution

### SQLite / Drift offline caching

Replace whole-list preferences storage with a structured offline database when data volume or synchronization warrants it. Use explicit profile/request tables, stable IDs, schema migrations, indexed village/mandal/vehicle/status/expiry columns, and a durable outbox for pending writes. Keep SharedPreferences for lightweight UI preferences. Query active rows by authoritative expiry and maintain a separate retention cleanup policy. A database migration must preserve the existing profile and urgent-load keys without silently losing local data.

### Low-budget FCM topic broadcasting

Planned topic convention: `topic_mandal_<name>`, for example `topic_mandal_kaikaluru`, `topic_mandal_mandavalli`, `topic_mandal_kalidindi`, and `topic_mandal_akividu`.

Users should explicitly choose subscriptions, with unsubscribe behavior when their preferences change. A trusted backend should validate and store each load before broadcasting a minimal request reference and expiry. Publish from a server, never from credentials embedded in the client. Opening a notification must fetch/recheck request status and TTL; a delayed or duplicate push must not resurrect a closed/expired load. Set delivery lifetime no longer than the remaining request TTL, deduplicate by request ID, rate-limit abuse, and avoid unnecessary personal data in lock-screen payloads.

FCM topics are delivery channels, not authorization boundaries or exact proximity matching. Evaluate provider limits and actual pilot usage before selecting a free-tier strategy; “low budget” is a design target, not a guarantee of zero operating cost. FCM, remote storage, permissions, and notifications are not currently wired into this application.

### Return-trip discount tagging — తిరుగు ప్రయాణం

Introduce a driver-declared return-trip tag, origin/destination corridor, optional departure window, and expiry. Show it as an opportunity for a negotiated backhaul rather than calculating or imposing a fare. Keep return-trip availability distinct from general availability, and validate cargo/access compatibility through the same direct-contact workflow. The tag is planned; there is no return-trip field or pricing engine in the current models.

### Additional architectural follow-through

- Introduce domain interfaces for driver profiles, directory queries, and load requests before adding remote implementations; preserve constructor injection for tests.
- Add structured pickup village/hub IDs, locally verified neighboring-cluster relationships, and road-access metadata without implying GPS precision.
- Establish last-confirmed availability timestamps and stale-profile indicators when profiles become shared across devices.
- Define conflict resolution, operation IDs, backend timestamps, pagination, and retry/outbox behavior for unreliable connectivity.
- Consolidate the older `LoadRequest` scaffold model into the active contract after checking migration needs.
- Validate Telugu wording and fonts on target devices; bundle a suitably licensed offline Telugu font if OS fallback proves inconsistent.
- Add searchable village/spot selection and optional standalone Telugu speech only after field evidence supports those changes.

## 10. Verification and release operations

Run the standard local checks from the repository root:

```sh
flutter pub get
flutter analyze
flutter test
```

| Test file | Coverage |
| --- | --- |
| `test/widget_test.dart` | Directory seed/filter behavior, village integrity, visiting-card navigation, three proximity sections, and narrow-screen text scaling. |
| `test/visiting_card_test.dart` | All five badges at small display size, PNG signature/full-card capture, card fields, narrow-screen enlarged text, and demo-call protection. |
| `test/driver_onboarding_test.dart` | Registration and validation, persisted fields, restart routing, concurrent partial updates, location/availability, Farmer View, corrupt data, save-failure preservation, and retry. |
| `test/proximity_matcher_test.dart` | Tier precedence from current/base village, same-mandal grouping, wider-belt fallback, stable/deduplicated order, unavailable/unknown cases, and all village-to-mandal mappings. |
| `test/load_request_test.dart` | Exact expiry boundary, restored/closed/future records, newest-first order, concurrent creation, invalid/corrupt data, live expiry removal, posting validation/persistence, and enlarged-text/keyboard layout. |

Setting `KOLLERU_RENDER_PREVIEWS=1` for the visiting-card tests writes optional PNGs under `build/previews/`. Widget-test fonts are not representative of the final phone’s Telugu typography; physical-device visual checks remain necessary.

On the current Windows development machine, Flutter plugin-link creation encountered disabled symlink support. Local directory junctions in the generated Windows plugin-link directory allowed dependency resolution without changing system settings. This is an environment accommodation, not an Android feature or a portable source dependency; a fresh checkout must provision its own supported Flutter/plugin environment.

For the planned Android release, configure signing securely and review the merged manifest and dependency requirements before generating an APK. `flutter build apk --release` is the intended build command after release configuration is ready; release APK generation and on-ground installation are not completed milestones in this snapshot. Retained desktop/iOS/web scaffolds do not imply those platforms have been validated; the PNG exporter uses `dart:io` and currently targets native mobile execution.

Pilot acceptance should include outdoor use on inexpensive phones, 2× text settings, Telugu rendering, keyboard-visible posting, no-network local browsing, app restart and resume, exact expired-load hiding, dialer handoff, real WhatsApp Status sharing, clear demo/local-only labeling, and participants’ understanding that arrangements are confirmed directly by phone.
