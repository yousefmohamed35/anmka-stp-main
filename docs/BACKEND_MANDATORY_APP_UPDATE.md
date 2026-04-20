# Mandatory app update (mobile clients)

This document describes how the **backend** should populate `GET /api/config/app` so the Flutter app can **block all usage** until the user updates from the store.

The mobile client already calls:

- **Method / path:** `GET https://stp.anmka.com/api/config/app`  
- **Response shape:** `{ "success": true, "data": { ... } }`  
- **Parsing:** Flutter reads **snake_case** fields inside `data` (see `AppConfig.fromJson` in `lib/models/app_config.dart`).

---

## Fields that control the update gate

| JSON field | Type | Required | Description |
|------------|------|----------|-------------|
| `min_version` | string | **Yes** | Minimum version the API still supports. If the installed app is **strictly lower**, the client **blocks** until the user updates. |
| `version` | string | **Yes** | **Latest published** version on the store (same rules as `min_version`). |
| `force_update` | boolean | **Yes** | If `true` **and** the installed app version is **strictly lower than** `version`, the client **blocks** (even when `min_version` alone would not). Use this to push everyone to the latest build. |
| `update_url` | string | No | Generic fallback URL (e.g. marketing page or single store link). Used when platform-specific URLs are missing. |
| `android_store_url` | string | No | **Preferred** for Android: Play Store listing or `market://` link. If omitted with `update_url` omitted, the client uses the default STP listing: [Google Play — STP](https://play.google.com/store/apps/details?id=com.anmka.stpnew). |
| `ios_store_url` | string | No | **Preferred** for iOS: App Store listing URL. |

**Version format:** `major.minor.patch`, optionally followed by `+build` (Flutter style), e.g. `1.0.0`, `1.0.0+8`, `2.3.12+105`. The client compares **core** (`major.minor.patch`) first, then the **integer build** after `+` if present. Missing `+` is treated as build `0` (so `1.0.0` is older than `1.0.0+1`). The installed string is built from the OS **version name** + **build number** the same way.

---

## Client blocking rules (summary)

The app reads the installed version from the OS (`versionName` / CFBundleShortVersionString), then:

1. **Block** if `installed < min_version` (string compared as semantic version).
2. **Else block** if `force_update == true` **and** `installed < version`.

If blocked, the user sees a full-screen message and an **Update now** button that opens, in order:

- **Android:** `android_store_url`, then `update_url`, then the default Play URL above.
- **iOS:** `ios_store_url`, then `update_url` (no default App Store URL in the client — set `ios_store_url` or `update_url` for iOS).

If no URL resolves (e.g. iOS with all null), the gate still blocks; the button shows an error snackbar.

---

## Example payloads

### No block (wide compatibility)

```json
{
  "success": true,
  "data": {
    "version": "1.5.0",
    "min_version": "1.0.0",
    "force_update": false,
    "update_url": "https://play.google.com/store/apps/details?id=com.anmka.stpnew",
    "android_store_url": "https://play.google.com/store/apps/details?id=com.anmka.stpnew",
    "ios_store_url": "https://apps.apple.com/app/idXXXXXXXX"
  }
}
```

### Hard floor: everyone below 1.4.0 must update

```json
{
  "success": true,
  "data": {
    "version": "1.6.0",
    "min_version": "1.4.0",
    "force_update": false,
    "android_store_url": "https://play.google.com/store/apps/details?id=com.anmka.stpnew",
    "ios_store_url": "https://apps.apple.com/app/idXXXXXXXX"
  }
}
```

### Everyone must move to latest published (`version`)

```json
{
  "success": true,
  "data": {
    "version": "2.0.0",
    "min_version": "1.0.0",
    "force_update": true,
    "android_store_url": "https://play.google.com/store/apps/details?id=com.anmka.stpnew",
    "ios_store_url": "https://apps.apple.com/app/idXXXXXXXX"
  }
}
```

---

## Consistency checklist for the backend team

1. **`min_version` ≤ `version`** in normal operation (or document intentional exceptions).
2. When raising `min_version`, ensure **store binaries** for that version are already published.
3. Provide **`android_store_url` / `ios_store_url` or `update_url`** whenever `min_version` or `force_update` can block users.
4. Admin dashboard (`GET/PUT /api/admin/app-config` per existing API notes) should edit the same logical document the public `GET /api/config/app` returns, so operators can roll out updates safely.

---

## Related code (Flutter)

- `lib/models/app_config.dart` — JSON model including new optional store URLs.  
- `lib/utils/mandatory_update_policy.dart` — blocking rules.  
- `lib/core/config/app_config_provider.dart` — loads config + `PackageInfo` at startup.  
- `lib/main.dart` — `MaterialApp.router` `builder` shows the gate when required.  
- `lib/screens/startup/mandatory_update_screen.dart` — blocking UI.
