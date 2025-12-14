# Offline Mode Implementation Requirements

This document outlines the requirements for implementing an offline mode in the wger Flutter app. The offline mode allows users to use the app without registration or user-specific API interactions, while preserving ingredient search as the only online feature.

## Table of Contents

1. [Overview](#overview)
2. [Architecture Changes](#architecture-changes)
3. [Authentication & Mode Selection](#authentication--mode-selection)
4. [Existing Cache Infrastructure](#existing-cache-infrastructure)
5. [Data Download System](#data-download-system)
6. [Local Storage for User Data](#local-storage-for-user-data)
7. [Provider Modifications](#provider-modifications)
8. [Feature Availability](#feature-availability)
9. [UI/UX Changes](#uiux-changes)
10. [Settings & Data Management](#settings--data-management)
11. [Backend Considerations](#backend-considerations)
12. [Implementation Phases](#implementation-phases)
13. [File Change Summary](#file-change-summary)

---

## Overview

### Goals

- Allow app usage without registration or login
- Download exercise data once during first use
- Store all user-created data (routines, meals, weight, etc.) locally
- Preserve ingredient search as online-only feature
- Ensure zero impact on existing online mode functionality
- **Reuse existing cache infrastructure** - extend rather than duplicate

### Guiding Principles

1. **Complete Isolation**: Online and offline code paths must not interfere with each other
2. **No Regressions**: Existing online functionality must remain unchanged
3. **Clear User Expectations**: Users must understand what works offline vs online
4. **Graceful Degradation**: Handle network failures elegantly
5. **Minimal Code Duplication**: Extend existing caching mechanisms rather than creating parallel systems

---

## Architecture Changes

### Current Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      main.dart                          │
│                    MultiProvider                        │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    AuthProvider                         │
│              (token, serverUrl, state)                  │
└─────────────────────────────────────────────────────────┘
                           │
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
    ┌────────────┐  ┌────────────┐  ┌────────────┐
    │ Exercises  │  │  Routines  │  │ Nutrition  │  ... other providers
    │  Provider  │  │  Provider  │  │  Provider  │
    └────────────┘  └────────────┘  └────────────┘
           │               │               │
           ▼               ▼               ▼
    ┌────────────┐  ┌────────────┐  ┌────────────┐
    │   wger     │  │   wger     │  │   wger     │
    │   API      │  │   API      │  │   API      │
    └────────────┘  └────────────┘  └────────────┘
```

### Proposed Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      main.dart                          │
│                    MultiProvider                        │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    AuthProvider                         │
│     (token, serverUrl, state, isOfflineMode)           │
└─────────────────────────────────────────────────────────┘
                           │
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
    ┌────────────┐  ┌────────────┐  ┌────────────┐
    │ Exercises  │  │  Routines  │  │ Nutrition  │  ... other providers
    │  Provider  │  │  Provider  │  │  Provider  │
    └────────────┘  └────────────┘  └────────────┘
           │               │               │
           ▼               ▼               ▼
    ┌────────────┐  ┌────────────┐  ┌────────────┐
    │   Data     │  │   Data     │  │   Data     │
    │  Source    │  │  Source    │  │  Source    │
    │ (abstract) │  │ (abstract) │  │ (abstract) │
    └────────────┘  └────────────┘  └────────────┘
        │    │          │    │          │    │
        ▼    ▼          ▼    ▼          ▼    ▼
    ┌──────┐┌──────┐┌──────┐┌──────┐┌──────┐┌──────┐
    │ API  ││Local ││ API  ││Local ││ API  ││Local │
    │Source││Source││Source││Source││Source││Source│
    └──────┘└──────┘└──────┘└──────┘└──────┘└──────┘
```

---

## Authentication & Mode Selection

### Current State (✅ IMPLEMENTED)

**File**: `lib/providers/auth.dart`

```dart
enum AuthState {
  updateRequired,
  loggedIn,
  loggedOut,
  offlineMode,  // ✅ Added
}
```

### Implemented Changes

#### 1. AuthState Enum - ✅ DONE

```dart
enum AuthState {
  updateRequired,
  loggedIn,
  loggedOut,
  offlineMode,
}
```

#### 2. Offline Mode Properties - ✅ DONE

```dart
class AuthProvider with ChangeNotifier {
  bool _isOfflineMode = false;
  bool get isOfflineMode => _isOfflineMode;

  Future<void> enterOfflineMode() async { /* implemented */ }
  Future<bool> checkOfflineMode() async { /* implemented */ }
}
```

#### 3. Preference Constants - ✅ DONE

**File**: `lib/helpers/consts.dart`

```dart
const PREFS_OFFLINE_MODE = 'offlineMode';
const PREFS_OFFLINE_DATA_VERSION = 'offlineDataVersion';
const PREFS_OFFLINE_DATA_DOWNLOADED = 'offlineDataDownloaded';
const PREFS_OFFLINE_LAST_SYNC = 'offlineLastSync';
```

#### 4. Auth Screen Redesign - ✅ DONE

**File**: `lib/screens/auth_screen.dart`

- Top section: "With Account" - login/register form
- Bottom section: "Without Account" - offline mode button
- Localized descriptions for both modes

---

## Existing Cache Infrastructure

### Current Caching Mechanisms

The app already has a robust caching system that we will **extend** rather than replace:

#### Exercise Data (Drift SQLite)

| Data Type | Storage | Cache Duration | Expiry Mechanism |
|-----------|---------|----------------|------------------|
| Exercises | `exercises.sqlite` | 7 days per exercise | `lastFetched` column |
| Muscles | `exercises.sqlite` | 7 days | `PREFS_LAST_UPDATED_MUSCLES` |
| Categories | `exercises.sqlite` | 7 days | `PREFS_LAST_UPDATED_CATEGORIES` |
| Languages | `exercises.sqlite` | 7 days | `PREFS_LAST_UPDATED_LANGUAGES` |
| Equipment | `exercises.sqlite` | 7 days | `PREFS_LAST_UPDATED_EQUIPMENT` |

#### Other Data (SharedPreferences)

| Data Type | Storage | Cache Duration | Expiry Mechanism |
|-----------|---------|----------------|------------------|
| Weight/Rep Units | SharedPreferences JSON | 20 days | `expiresIn` field |
| Ingredients | `ingredients.sqlite` | 20 days | `lastFetched` column |

### Key Insight: Cache is Persistent

**Important**: The existing cache stores data in SQLite - it's NOT deleted when it "expires". The expiry timestamp only determines whether to **check for updates** from the API. If the API is unavailable, the cached data is still usable.

### Strategy: "Permanent Cache" Mode

Instead of creating new download infrastructure, we extend the existing pattern:

#### Current Pattern
```dart
// Existing: validTill = 7 days from now
validTill = DateTime.now().add(const Duration(days: EXERCISE_CACHE_DAYS));
```

#### Extended Pattern
```dart
// New: Support permanent caching
validTill = permanent
    ? DateTime(9999, 12, 31)  // "Never expires"
    : DateTime.now().add(const Duration(days: EXERCISE_CACHE_DAYS));
```

### Benefits of This Approach

1. **No duplicate code** - Reuses existing fetch, parse, and store logic
2. **Same data format** - No migration needed
3. **Backward compatible** - Online mode continues working exactly as before
4. **Unified settings** - One place to manage cache (Settings > Cache)
5. **Simpler testing** - Existing cache tests still apply

---

## Data Download System

### Overview

The data download system now **extends existing cache methods** rather than creating parallel infrastructure.

### Approach: Extend Existing Methods

#### ExercisesProvider Modifications

Add `permanent` parameter to existing fetch methods:

```dart
/// Fetches and sets the available muscles
///
/// If [permanent] is true, cache never expires (for offline mode)
/// If [forceRefresh] is true, fetches from API even if cache is valid
Future<void> fetchAndSetMuscles(
  ExerciseDatabase database, {
  bool permanent = false,
  bool forceRefresh = false,
}) async {
  final prefs = PreferenceHelper.asyncPref;
  var validTill = DateTime.parse((await prefs.getString(PREFS_LAST_UPDATED_MUSCLES))!);

  // Skip cache check if forcing refresh
  if (!forceRefresh && validTill.isAfter(DateTime.now())) {
    final muscles = await database.select(database.muscles).get();
    if (muscles.isNotEmpty) {
      _muscles = muscles.map((e) => e.data).toList();
      return;
    }
  }

  // Fetch from API and save to DB
  await fetchAndSetMusclesFromApi();
  await database.delete(database.muscles).go();
  await Future.forEach(_muscles, (e) async {
    await database.into(database.muscles).insert(MusclesCompanion.insert(id: e.id, data: e));
  });

  // Set expiry based on permanent flag
  validTill = permanent
      ? DateTime(9999, 12, 31)
      : DateTime.now().add(const Duration(days: EXERCISE_CACHE_DAYS));
  await prefs.setString(PREFS_LAST_UPDATED_MUSCLES, validTill.toIso8601String());
}
```

Apply same pattern to:
- `fetchAndSetCategories()`
- `fetchAndSetLanguages()`
- `fetchAndSetEquipments()`
- `fetchAndSetAllExercises()`

#### RoutinesProvider Modifications

```dart
Future<void> fetchAndSetUnits({bool permanent = false}) async {
  // ... existing logic ...

  final cacheData = {
    'date': DateTime.now().toIso8601String(),
    'expiresIn': permanent
        ? DateTime(9999, 12, 31).toIso8601String()
        : DateTime.now().add(const Duration(days: DAYS_TO_CACHE)).toIso8601String(),
    'repetitionUnits': _repetitionUnits.map((e) => e.toJson()).toList(),
    'weightUnit': _weightUnits.map((e) => e.toJson()).toList(),
  };
  prefs.setString(PREFS_WORKOUT_UNITS, json.encode(cacheData));
}
```

### Data Setup Screen

**File**: `lib/screens/data_setup_screen.dart`

This screen appears:
1. **For offline mode**: After selecting "Continue without account" (if no data cached)
2. **For online mode**: Optionally via Settings > "Download all exercises"

```dart
class DataSetupScreen extends StatefulWidget {
  /// If true, sets permanent cache (never expires)
  final bool permanent;

  /// Called when setup is complete
  final VoidCallback onComplete;

  const DataSetupScreen({
    required this.permanent,
    required this.onComplete,
  });
}
```

### Download Flow

```
┌────────────────────────┐
│  Auth Screen           │
│  - Login/Register      │
│  - Continue Offline    │
└──────────┬─────────────┘
           │
           ▼
┌────────────────────────┐
│  Check cache status    │
│  (has essential data?) │
└──────────┬─────────────┘
           │
     ┌─────┴─────┐
     │           │
     ▼           ▼
┌─────────┐  ┌────────────────┐
│ Has     │  │ Data Setup     │
│ Data    │  │ Screen         │
└────┬────┘  └───────┬────────┘
     │               │
     │               ▼
     │       ┌────────────────┐
     │       │ Call existing  │
     │       │ fetch methods  │
     │       │ with:          │
     │       │ - permanent=T  │
     │       │ - forceRefresh │
     │       └───────┬────────┘
     │               │
     └───────┬───────┘
             │
             ▼
     ┌────────────────┐
     │  Home Screen   │
     └────────────────┘
```

### Progress Tracking

Since we're reusing existing methods, progress tracking wraps around them:

```dart
class DataSetupService {
  final ExercisesProvider exercisesProvider;
  final RoutinesProvider routinesProvider;

  Stream<SetupProgress> setupData({required bool permanent}) async* {
    yield SetupProgress(step: 'muscles', progress: 0.0);
    await exercisesProvider.fetchAndSetMuscles(
      exercisesProvider.database,
      permanent: permanent,
      forceRefresh: true,
    );

    yield SetupProgress(step: 'categories', progress: 0.15);
    await exercisesProvider.fetchAndSetCategories(
      exercisesProvider.database,
      permanent: permanent,
      forceRefresh: true,
    );

    yield SetupProgress(step: 'equipment', progress: 0.30);
    await exercisesProvider.fetchAndSetEquipments(
      exercisesProvider.database,
      permanent: permanent,
      forceRefresh: true,
    );

    yield SetupProgress(step: 'languages', progress: 0.45);
    await exercisesProvider.fetchAndSetLanguages(
      exercisesProvider.database,
      permanent: permanent,
      forceRefresh: true,
    );

    yield SetupProgress(step: 'units', progress: 0.55);
    await routinesProvider.fetchAndSetUnits(permanent: permanent);

    yield SetupProgress(step: 'exercises', progress: 0.60);
    await exercisesProvider.fetchAndSetAllExercisesPermanent(
      onProgress: (current, total) {
        // Exercises are 40% of total (0.60 to 1.0)
        final exerciseProgress = current / total;
        yield SetupProgress(
          step: 'exercises',
          progress: 0.60 + (exerciseProgress * 0.40),
          detail: '$current / $total',
        );
      },
    );

    yield SetupProgress(step: 'complete', progress: 1.0);
  }
}

class SetupProgress {
  final String step;
  final double progress;  // 0.0 to 1.0
  final String? detail;
  final String? error;
}
```

---

## Local Storage for User Data

### Current Local Storage

| Data | Storage | Location |
|------|---------|----------|
| Exercises | Drift SQLite | `exercises.sqlite` |
| Ingredients | Drift SQLite | `ingredients.sqlite` |
| User credentials | SharedPreferences | - |
| Theme | SharedPreferences | - |

### New Local Storage Requirements

For offline mode, user-created data (routines, meals, weight) needs local storage.

#### 1. Offline User Data Database

**File**: `lib/database/offline/offline_user_database.dart`

```dart
@DriftDatabase(tables: [
  OfflineRoutines,
  OfflineDays,
  OfflineSlots,
  OfflineSlotEntries,
  OfflineSessions,
  OfflineLogs,
  OfflineNutritionPlans,
  OfflineMeals,
  OfflineMealItems,
  OfflineNutritionDiary,
  OfflineWeightEntries,
  OfflineMeasurementCategories,
  OfflineMeasurementEntries,
])
class OfflineUserDatabase extends _$OfflineUserDatabase {
  OfflineUserDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}
```

#### 2. ID Generation Strategy

For offline-created entities, use UUIDs:

```dart
import 'package:uuid/uuid.dart';

class OfflineIdGenerator {
  static const _uuid = Uuid();
  static String generate() => _uuid.v4();
}
```

---

## Provider Modifications

### Strategy: Data Source Abstraction

For user data providers, create abstract data sources:

```dart
abstract class RoutineDataSource {
  Future<List<Routine>> fetchAllRoutines();
  Future<Routine> createRoutine(Routine routine);
  // ...
}

class OnlineRoutineDataSource implements RoutineDataSource {
  // Uses WgerBaseProvider (existing logic)
}

class OfflineRoutineDataSource implements RoutineDataSource {
  // Uses OfflineUserDatabase
}
```

### ExercisesProvider Changes

Minimal changes - just add `permanent` and `forceRefresh` parameters to existing methods.

### Providers Requiring Data Source Abstraction

| Provider | Changes Needed |
|----------|----------------|
| RoutinesProvider | Data source abstraction for user routines |
| NutritionPlansProvider | Data source abstraction for user plans |
| BodyWeightProvider | Data source abstraction for weight entries |
| MeasurementProvider | Data source abstraction for measurements |
| GalleryProvider | Disable in offline mode |
| UserProvider | Return synthetic profile in offline mode |
| **ExercisesProvider** | **Only add `permanent`/`forceRefresh` params** |

---

## Feature Availability

### Feature Matrix

| Feature | Online Mode | Offline Mode | Notes |
|---------|:-----------:|:------------:|-------|
| **Exercises** |
| View exercise list | ✅ | ✅ | Downloaded data |
| View exercise details | ✅ | ✅ | Downloaded data |
| Search exercises | ✅ | ✅ | Local search |
| Filter exercises | ✅ | ✅ | Local filtering |
| Submit new exercise | ✅ | ❌ | Requires account |
| **Workouts** |
| View routines | ✅ | ✅ | Local storage |
| Create routine | ✅ | ✅ | Local storage |
| Edit routine | ✅ | ✅ | Local storage |
| Delete routine | ✅ | ✅ | Local storage |
| Gym mode | ✅ | ✅ | Local storage |
| Log workouts | ✅ | ✅ | Local storage |
| **Nutrition** |
| View meal plans | ✅ | ✅ | Local storage |
| Create meal plan | ✅ | ✅ | Local storage |
| Search ingredients | ✅ | ⚠️ | Online only |
| Add meal items | ✅ | ⚠️ | Cached ingredients only |
| Log meals | ✅ | ✅ | Local storage |
| Barcode scanning | ✅ | ❌ | Requires API |
| **Body Tracking** |
| Log weight | ✅ | ✅ | Local storage |
| Log measurements | ✅ | ✅ | Local storage |
| **Other** |
| User gallery | ✅ | ❌ | Requires account |
| Dark mode | ✅ | ✅ | Local preference |

---

## UI/UX Changes

### 1. Auth Screen - ✅ DONE

Redesigned with top/bottom split:
- Top: "With Account" section (login/register)
- Bottom: "Without Account" section (offline mode)

### 2. Data Setup Screen (NEW)

```
┌─────────────────────────────────────────┐
│                                         │
│           [wger logo]                   │
│                                         │
│      Setting up your app...             │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │████████████░░░░░░░░░░░░░░░░░░░░│   │
│   └─────────────────────────────────┘   │
│              45%                        │
│                                         │
│   Downloading exercises (456/1024)      │
│                                         │
│         [Cancel]                        │
│                                         │
└─────────────────────────────────────────┘
```

### 3. Settings Integration

Add to existing cache settings:

```dart
// In Settings > Cache section
ListTile(
  leading: const Icon(Icons.download),
  title: Text('Download all exercise data'),
  subtitle: Text('For offline use or to reduce mobile data'),
  onTap: () => Navigator.pushNamed(context, DataSetupScreen.routeName),
),

// Show last sync time if permanent cache is set
if (hasPermanentCache)
  ListTile(
    leading: const Icon(Icons.schedule),
    title: Text('Exercise data last updated'),
    subtitle: Text(formatDate(lastSyncDate)),
  ),
```

---

## Settings & Data Management

### Unified Cache Management

The existing Settings > Cache section will be extended:

```dart
// Existing
const SettingsExerciseCache(),  // Clear cache button
const SettingsIngredientCache(),

// New additions
ListTile(
  title: Text('Download all exercises'),
  subtitle: Text('~50MB, for offline use'),
  trailing: Icon(Icons.download),
  onTap: () => _startDataSetup(context, permanent: true),
),

if (isOfflineMode || hasPermanentCache) ...[
  ListTile(
    title: Text('Last updated'),
    subtitle: Text(_formatDate(lastSyncDate)),
  ),
  ListTile(
    title: Text('Update exercise data'),
    onTap: () => _startDataSetup(context, permanent: true),
  ),
],
```

---

## Backend Considerations

### ⚠️ BLOCKER: Authentication Required for API Access

**Critical Discovery**: The current Flutter app implementation requires authentication for ALL API calls, including read-only exercise data endpoints.

#### Current Implementation Problem

In `lib/providers/base_provider.dart`:

```dart
class WgerBaseProvider {
  AuthProvider auth;

  Future<dynamic> fetch(Uri uri) async {
    final response = await client.get(
      uri,
      headers: getDefaultHeaders(includeAuth: true),  // Always includes auth!
    );
    // ...
  }

  Map<String, String> getDefaultHeaders({bool includeAuth = false}) {
    // ...
    if (includeAuth) {
      out[HttpHeaders.authorizationHeader] = 'Token ${auth.token}';
    }
    return out;
  }

  Uri makeUrl(String path, ...) {
    return makeUri(auth.serverUrl!, path, ...);  // Requires serverUrl!
  }
}
```

**Problems for Offline Mode**:
1. `auth.token` is `null` in offline mode
2. `auth.serverUrl` is `null` in offline mode
3. All `fetch()` calls include `includeAuth: true`

#### Backend Changes Required

The wger backend needs to allow **unauthenticated read-only access** to the following endpoints:

| Endpoint | Purpose | Required for Offline |
|----------|---------|---------------------|
| `GET /api/v2/exercise` | List all exercises | ✅ Yes |
| `GET /api/v2/exerciseinfo/{id}` | Exercise details | ✅ Yes |
| `GET /api/v2/exercisecategory` | Exercise categories | ✅ Yes |
| `GET /api/v2/muscle` | Muscle list | ✅ Yes |
| `GET /api/v2/equipment` | Equipment list | ✅ Yes |
| `GET /api/v2/language` | Language list | ✅ Yes |
| `GET /api/v2/setting-weightunit` | Weight units | ✅ Yes |
| `GET /api/v2/setting-repetitionunit` | Repetition units | ✅ Yes |

**Note**: User-specific endpoints (routines, nutrition plans, weight entries, etc.) should remain authenticated.

#### Flutter Changes Required After Backend Update

Once the backend supports unauthenticated access, the Flutter app needs:

1. **New `PublicApiProvider`** or modify `WgerBaseProvider`:
   ```dart
   class PublicApiProvider {
     static const defaultServerUrl = 'https://wger.de';

     Future<dynamic> fetchPublic(Uri uri) async {
       final response = await client.get(
         uri,
         headers: {
           HttpHeaders.contentTypeHeader: 'application/json; charset=UTF-8',
           // No auth header
         },
       );
       // ...
     }
   }
   ```

2. **Modify `ExercisesProvider`** to use public endpoints for exercise data

3. **Modify `RoutinesProvider.fetchAndSetUnits()`** to use public endpoint

#### Alternative Approaches (If Backend Can't Be Changed)

If unauthenticated access cannot be enabled:

**Option A: Pre-download Before Offline Mode**
- Show download screen BEFORE entering offline mode
- User must have internet during initial setup
- Store data with permanent cache
- Problem: First-time users can't start offline immediately

**Option B: Bundled Data**
- Include exercise data as app asset
- Update data with app releases
- Problem: Stale data, larger app size

**Option C: Temporary Anonymous Token**
- Backend provides read-only anonymous token
- App uses this token for public data
- Problem: Still requires backend changes

### Recommended Backend Implementation

```python
# In Django REST Framework views

class ExerciseViewSet(viewsets.ReadOnlyModelViewSet):
    """
    Exercise data is public and readable without authentication.
    """
    permission_classes = [AllowAny]  # Changed from IsAuthenticated
    # ...

class MuscleViewSet(viewsets.ReadOnlyModelViewSet):
    permission_classes = [AllowAny]
    # ...

# Similar for: ExerciseCategoryViewSet, EquipmentViewSet, LanguageViewSet
# WeightUnitViewSet, RepetitionUnitViewSet
```

### Future Optimization (Optional)

A bulk export endpoint could reduce download time:

```
GET /api/v2/exercise/bulk-export
Accept: application/json

Response:
{
  "version": "2024.1",
  "generated_at": "2024-01-15T10:30:00Z",
  "exercises": [...],
  "categories": [...],
  "muscles": [...],
  "equipment": [...],
  "languages": [...]
}
```

---

## Implementation Phases

### ⏸️ BLOCKED: Waiting for Backend Changes

**Phase 2 and beyond are blocked** until the backend supports unauthenticated access to exercise-related endpoints.

### Phase 1: Foundation - ✅ COMPLETE

- [x] Add `AuthState.offlineMode` to auth provider
- [x] Add offline mode preference constants
- [x] Add `enterOfflineMode()` and `checkOfflineMode()` methods
- [x] Modify `tryAutoLogin()` to check for offline mode
- [x] Redesign auth screen with offline mode option
- [x] Add localization strings
- [x] Add `CACHE_NEVER_EXPIRES` constant for permanent caching

### Phase 1.5: Backend Changes - 🚧 REQUIRED

**Goal**: Enable unauthenticated read-only access to exercise data

**Backend Tasks**:
- [ ] Set `permission_classes = [AllowAny]` for exercise endpoints
- [ ] Set `permission_classes = [AllowAny]` for muscle endpoint
- [ ] Set `permission_classes = [AllowAny]` for category endpoint
- [ ] Set `permission_classes = [AllowAny]` for equipment endpoint
- [ ] Set `permission_classes = [AllowAny]` for language endpoint
- [ ] Set `permission_classes = [AllowAny]` for weight unit endpoint
- [ ] Set `permission_classes = [AllowAny]` for repetition unit endpoint
- [ ] Test endpoints work without authentication
- [ ] Consider rate limiting for unauthenticated requests

**Flutter Preparation Tasks** (can be done in parallel):
- [ ] Create `PublicApiProvider` class for unauthenticated requests
- [ ] Add `permanent` and `forceRefresh` params to cache methods (ready for use)

### Phase 2: Extended Cache System - ⏸️ BLOCKED

**Goal**: Add permanent cache support to existing methods

**Blocked by**: Phase 1.5 (Backend changes required)

**Tasks** (ready to implement once backend is updated):
- [ ] Add `permanent` and `forceRefresh` params to `fetchAndSetMuscles()`
- [ ] Add `permanent` and `forceRefresh` params to `fetchAndSetCategories()`
- [ ] Add `permanent` and `forceRefresh` params to `fetchAndSetEquipments()`
- [ ] Add `permanent` and `forceRefresh` params to `fetchAndSetLanguages()`
- [ ] Add `permanent` param to `fetchAndSetUnits()`
- [ ] Create `fetchAndSetAllExercisesPermanent()` with progress callback
- [ ] Create `DataSetupService` to orchestrate downloads with progress
- [ ] Create `PublicApiProvider` for unauthenticated requests

**Files to modify**:
- `lib/providers/exercises.dart`
- `lib/providers/routines.dart`
- `lib/providers/base_provider.dart` (or create new public provider)

**New files**:
- `lib/services/data_setup_service.dart`
- `lib/providers/public_api_provider.dart`

---

### Phase 3: Data Setup Screen - ⏸️ BLOCKED

**Goal**: UI for initial data download

**Blocked by**: Phase 2

**Tasks**:
- [ ] Create data setup screen with progress indicator
- [ ] Integrate with `DataSetupService`
- [ ] Add cancel/retry functionality
- [ ] Route to setup screen when needed (offline mode first launch)
- [ ] Add "Download all" option to Settings

**New files**:
- `lib/screens/data_setup_screen.dart`

**Files to modify**:
- `lib/main.dart` (routing logic)
- `lib/widgets/core/settings.dart`

---

### Phase 4: Local User Data Storage - ⏸️ BLOCKED

**Goal**: Store user-created data locally for offline mode

**Blocked by**: Phase 3

**Tasks**:
- [ ] Create Drift database for offline user data
- [ ] Define tables for routines, nutrition, weight, measurements
- [ ] Implement UUID-based ID generation
- [ ] Add database to service locator

**New files**:
- `lib/database/offline/offline_user_database.dart`

---

### Phase 5: Provider Data Source Abstraction - ⏸️ BLOCKED

**Goal**: Enable providers to work with both online and offline data sources

**Blocked by**: Phase 4

**Tasks**:
- [ ] Create abstract data source interfaces
- [ ] Implement offline data sources
- [ ] Modify providers to use data source abstraction
- [ ] Update provider initialization in main.dart

**Files to modify**:
- `lib/providers/routines.dart`
- `lib/providers/nutrition.dart`
- `lib/providers/body_weight.dart`
- `lib/providers/measurement.dart`
- `lib/main.dart`

**New files**:
- `lib/providers/data_sources/routine_data_source.dart`
- `lib/providers/data_sources/nutrition_data_source.dart`
- `lib/providers/data_sources/weight_data_source.dart`
- `lib/providers/data_sources/measurement_data_source.dart`

---

### Phase 6: App Flow Integration - ⏸️ BLOCKED

**Goal**: Integrate offline mode into app navigation flow

**Blocked by**: Phase 5

**Tasks**:
- [ ] Modify home screen initialization for offline mode
- [ ] Skip user-specific API calls in offline mode
- [ ] Handle ingredient search in offline mode
- [ ] Hide gallery tab in offline mode

**Files to modify**:
- `lib/screens/home_tabs_screen.dart`
- `lib/widgets/nutrition/forms/meal_item_form.dart`

---

### Phase 7: Polish & Settings - ⏸️ BLOCKED

**Goal**: Complete the user experience

**Blocked by**: Phase 6

**Tasks**:
- [ ] Add offline mode indicator (optional banner)
- [ ] Add "Update data" option in settings
- [ ] Show last sync timestamp
- [ ] Comprehensive error handling

---

## File Change Summary

### Files Already Modified (Phase 1) ✅

| File | Changes |
|------|---------|
| `lib/providers/auth.dart` | Added `offlineMode` state, `enterOfflineMode()`, `checkOfflineMode()` |
| `lib/helpers/consts.dart` | Added `PREFS_OFFLINE_*` constants, `CACHE_NEVER_EXPIRES` |
| `lib/screens/auth_screen.dart` | Complete redesign with offline mode option |
| `lib/main.dart` | Handle `AuthState.offlineMode` in routing |
| `lib/l10n/app_en.arb` | Added localization strings |
| `lib/l10n/app_de.arb` | Added German translations |

### Files to Modify (Phases 2-7) - ⏸️ BLOCKED

| File | Changes |
|------|---------|
| `lib/providers/exercises.dart` | Add `permanent`/`forceRefresh` params |
| `lib/providers/routines.dart` | Add `permanent` param to `fetchAndSetUnits()`, data source abstraction |
| `lib/providers/nutrition.dart` | Data source abstraction |
| `lib/providers/body_weight.dart` | Data source abstraction |
| `lib/providers/measurement.dart` | Data source abstraction |
| `lib/screens/home_tabs_screen.dart` | Skip API calls in offline mode |
| `lib/widgets/core/settings.dart` | Add download/update options |
| `lib/core/locator.dart` | Register offline database |

### New Files to Create

| File | Purpose |
|------|---------|
| `lib/services/data_setup_service.dart` | Orchestrate data download with progress |
| `lib/screens/data_setup_screen.dart` | Download progress UI |
| `lib/database/offline/offline_user_database.dart` | Local user data storage |
| `lib/providers/data_sources/*.dart` | Abstract data source interfaces |

### Dependencies

Add to `pubspec.yaml`:

```yaml
dependencies:
  uuid: ^4.2.1  # For offline ID generation
  # drift already included
  # shared_preferences already included
```

---

## Testing Considerations

### Unit Tests

- Permanent cache flag behavior
- Offline data source implementations
- ID generation

### Integration Tests

- Full offline flow (first launch → download → use)
- Data persistence across app restarts
- Online mode still works correctly

### Manual Testing Checklist

- [ ] First launch offline mode selection
- [ ] Data setup screen progress and completion
- [ ] Exercise list populated after setup
- [ ] App restart preserves data
- [ ] Online mode still works correctly
- [ ] Settings > Download all exercises works

---

## Open Questions

1. **Image Downloads**: Should exercise images be downloaded? (Significant storage impact)
2. **Data Migration**: If user creates account later, should offline data be synced?
3. **Common Ingredients**: Pre-download common ingredients for offline use?

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-XX-XX | Initial requirements document |
| 1.1 | 2024-XX-XX | Phase 1 implemented (auth screen, offline mode state) |
| 1.2 | 2024-XX-XX | Strategic refinement: extend existing cache infrastructure instead of creating parallel systems |
| 1.3 | 2024-12-14 | **BLOCKER IDENTIFIED**: Backend requires authentication for all API calls. Added Phase 1.5 for backend changes. All subsequent phases blocked until backend supports unauthenticated read-only access to exercise data endpoints. |
