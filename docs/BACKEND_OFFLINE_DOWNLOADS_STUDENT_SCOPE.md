# Offline downloads: per-student (per account) behavior — backend handoff

## Summary for backend / product

Offline lesson videos are stored **only on the device** (app private storage + local SQLite). The mobile app now **scopes** that data to the **signed-in user id** (`owner_user_id` in the local table, aligned with the authenticated account from your API, typically `GET /me` → `data.id`).

Implications:

1. **No server round-trip is required** to delete files on the phone. “Delete downloads for student X” on a **web admin dashboard** cannot remove bytes from student Y’s device directly; the student app must run delete logic locally (or receive a signal, then delete — see optional API below).

2. **Per-student on a shared tablet**: when one family device is used by multiple accounts (logout / login), each account only **lists**, **plays**, and **bulk-clears** its own offline rows. Another account’s files remain on disk but are **not shown** and are **not** removed by “clear all” for the current user.

3. **User id on the client**: after login/register/social login, the app persists the account id in secure storage (`logged_in_user_id`). If an old session exists without that key, the app may call **`GET /me`** once when initialising downloads to backfill the id (same `data.id` field you already return).

## What the app does today (Flutter)

| Action | Scope |
|--------|--------|
| Downloads list (`downloads_screen`) | Rows where `owner_user_id` = current account id |
| Delete one video (trash on card) | Same scope + delete file from disk |
| Clear all offline videos (Downloads header **or** Settings) | Deletes **only** files + rows for the **current** account |
| DB migration | Existing installs get column `owner_user_id`; legacy rows with `NULL` are assigned **once** to the first signed-in account that opens the DB after upgrade (documented edge case for old data) |

## Optional backend features (not implemented in app unless you add them)

These are **ideas** if you want dashboard-driven behaviour:

1. **Revoke downloads globally**  
   You already can expose `features.downloads_enabled` (or equivalent) in app config so new downloads are blocked after sync.

2. **Force clear on next sync**  
   Add a monotonic integer or timestamp, e.g. `offline_downloads_policy_version`, on `GET /me` or app config. The app compares to a local copy; if the server value is newer, run the same routine as “clear all offline videos” once, then persist the new version. That gives admins a “reset offline copies” lever without push infrastructure.

3. **Audit only**  
   `POST /lessons/{id}/download-started` / `download-deleted` — purely server-side analytics; does not remove local files by itself.

## API fields the client already uses

- **Login / register / social**: user object includes `id` (string or numeric JSON — client normalises with `toString()`).
- **`GET /me`**: response `data` includes `id` for backfilling `logged_in_user_id` when missing.

No new endpoints are **required** for the per-student local delete feature described above.

## Related code (Flutter)

- `lib/services/video_download_service.dart` — `owner_user_id`, `clearAllDownloadedVideos()` (scoped to current user), migration.
- `lib/services/token_storage_service.dart` — `saveLoggedInUserId` / `getLoggedInUserId`.
- `lib/services/auth_service.dart` — persists user id on successful auth (not on token refresh).
- `lib/screens/secondary/downloads_screen.dart` — bulk clear control in the header.

---

*Use this document as the “message to backend” for alignment on what is local-only vs what would need new APIs.*
