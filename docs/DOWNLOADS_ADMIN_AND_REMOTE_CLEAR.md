# Offline video downloads: admin control and clearing on student devices

This document explains how download control works technically, what the mobile app can and cannot do, and how the **“clear all offline videos”** action fits in.

## What is stored on the student device?

Lesson videos downloaded for offline viewing are saved in the app’s **private storage** (application support directory) on that phone or tablet. A small **local SQLite database** (`downloaded_videos.db`) stores metadata (lesson id, file path, titles, etc.).

- **Deleting data on a user’s device remotely** (without the user opening the app) is not possible with a normal LMS + consumer app unless you add extra infrastructure (push commands, MDM, etc.).
- **An admin dashboard cannot directly reach into each student’s file system** the way it can delete rows on a server database.

So “remove downloads for every student” is implemented as a **combination** of server-side policy and on-device behavior.

## 1. Block *new* downloads for everyone (dashboard / backend)

Your backend already has a natural place for a global flag in the **app config** payload (see `FeaturesConfig` in the Flutter app):

- JSON path: `features.downloads_enabled` (boolean)
- When `false`, the app should hide download UI and refuse new downloads after the config is refreshed (typically on next app launch or when you add a “refresh config” call).

**Dashboard work:** expose a toggle that updates this field in whatever API serves `GET …/app-config` (or equivalent). All students receive the same value on the next fetch.

*Optional per-lesson control:* return fields such as `downloadable` / `allow_video_download` on lesson or lesson-content API responses and hide the download button when `false`.

## 2. Clear files that are *already* on the device

### A. Student-initiated (implemented in the app)

**Settings → General Settings → “Clear all offline videos”** / **«مسح كل الفيديوهات المحمّلة»**, and the same action from **Progress → Downloads** (header icon when the list is non-empty) (localized string keys: `clearAllOfflineVideos`, etc.):

- Deletes every video file referenced in the local database **for the currently signed-in student account** (`owner_user_id` matches the authenticated user id).
- Clears those rows only from the offline downloads table (other accounts on the same device keep their rows/files until they clear or delete).
- Affects **only the current device** and **only this install** of the app.

Use case: policy change, freeing storage, or admin asking users to tap this after revoking downloads.

### B. Admin “for every student” without touching each phone

To approximate “clear for all students,” you need the **app to decide** to wipe local data when it learns the server revoked downloads. For example:

1. **Versioned flag**  
   - Backend stores `downloads_policy_version` (integer) or `downloads_revoked_at` (ISO timestamp).  
   - App config or user profile includes the current value.  
   - App persists `last_known_downloads_policy_version` locally.  
   - If server value is newer than local → run the same logic as “clear all offline videos” once, then save the new version.

2. **Explicit command** (heavier)  
   - `GET /me/device-commands` returns `{ "action": "clear_offline_videos", "id": "…" }`.  
   - App executes clear, then `POST` ack so the command is not repeated.

Until that API exists, **per-device clearing** is limited to:

- The new **in-app** bulk delete, or  
- User clearing **app storage** in Android/iOS settings (nuclear option).

## 3. Summary table

| Goal | Where it happens | Notes |
|------|------------------|--------|
| Stop new downloads globally | Dashboard → API `features.downloads_enabled` | All students after config refresh |
| Stop new downloads per lesson | Lesson/content API flags | Finer control |
| Remove already downloaded files on one device | App: **Clear all offline videos** | Implemented |
| Remove files on all devices automatically | Backend signal + app logic on sync | Requires API + client work (see §2B) |

## 4. Related code (Flutter)

- `VideoDownloadService.clearAllDownloadedVideos()` — deletes files + clears DB rows for the **current** user only.
- `SettingsScreen` and `DownloadsScreen` — entry points for the user-facing action.
- `docs/BACKEND_OFFLINE_DOWNLOADS_STUDENT_SCOPE.md` — concise backend handoff for per-account scoping.
- `AppConfig` / `FeaturesConfig.downloadsEnabled` — global feature flag (wire UI when ready).
- `DownloadManager` — writes files under `getApplicationSupportDirectory()`.

---

*Last updated: product doc aligned with offline download storage and settings clear action.*
