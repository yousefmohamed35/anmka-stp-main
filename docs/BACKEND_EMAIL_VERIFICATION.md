# Email verification — backend contract (mobile app)

**Status:** Backend is implemented; the mobile app is aligned with this contract.

This document describes what the **Anmka STP mobile app** expects from the API so that users **register with an unverified email**, **confirm via link**, and **cannot sign in with password (or social)** until the email is verified.

---

## 1. User object: `email_verified`

For every auth response that includes a user payload (`POST /auth/register`, `POST /auth/login`, `POST /auth/social-login`, and ideally `GET /auth/me`), include a boolean:

| Field            | Type    | Required | Notes |
|------------------|---------|----------|--------|
| `email_verified` | boolean | **Yes**  | `false` until the user completes verification; `true` after. |

**Backward compatibility:** If this field is **omitted**, the app currently treats the user as **verified** (so existing environments keep working until you roll out the flag).

**Naming:** The app also accepts camelCase `emailVerified` if you prefer that in JSON.

> Note: The app has a separate field `is_verified` in the user model (legacy / other meaning). Please use **`email_verified`** specifically for **email confirmation**, not for admin approval, unless you intentionally map them the same on the server.

---

## 2. Registration (`POST /auth/register`)

**Desired behavior**

1. Create the user with `email_verified: false`.
2. Send a verification email with a link (or deep link) to your verification endpoint.
3. Response should make it clear the account exists but email is not confirmed yet.

**Response shape (success)**

- `success: true`
- `message` — human-readable (optional but useful), e.g. “Check your email to verify your account.”
- `data` — user object **must** include `"email_verified": false`.

**Tokens**

- **Recommended:** Do **not** return access/refresh tokens until `email_verified` is `true`. The app will **not** store tokens when `email_verified` is `false` and will show the “verify your email” screen instead of logging the user in.
- If you still return tokens while `email_verified` is `false`, the app will **ignore** them and will **not** navigate into the main app until the user verifies (same as no tokens).

**Admin / instructor `PENDING` flow**

If you already return `status: "PENDING"` for accounts awaiting admin approval, keep that behavior. It is handled **before** the email-verification branch. Email verification can still apply to students who are auto-approved.

---

## 3. Login (`POST /auth/login`)

**When credentials are correct but email is not verified**

Choose **one** (or both) of these so the app can show a clear message:

### Option A — HTTP error (recommended for password login)

- Status code: **`403 Forbidden`** or **`401 Unauthorized`** — the app treats **`code: "EMAIL_NOT_VERIFIED"`** the same on either status. For **`403`** only, it also treats some verification-related **messages** as unverified-email when `code` is omitted.
- JSON body example:

```json
{
  "success": false,
  "message": "Please verify your email before signing in.",
  "code": "EMAIL_NOT_VERIFIED"
}
```

The app maps `code: "EMAIL_NOT_VERIFIED"` (case-insensitive) to a dedicated UX path. It also tries to detect verification-related messages when `code` is missing.

### Option B — HTTP 200 with `success: true` (not recommended)

If you return `success: true` with tokens and `data.user.email_verified: false`, the app will **reject** login client-side, clear nothing (tokens were not saved), and show “verify your email” messaging. Prefer **Option A** to avoid issuing tokens at all.

**When login should succeed**

- `success: true`
- User has `email_verified: true`
- Valid `accessToken` / `refreshToken` (or whatever field names you already use — the app supports `accessToken`, `token`, `access_token`, etc., as today).

---

## 4. Social login (`POST /auth/social-login`)

Apply the **same rules** as password login:

- If the linked account’s email is not verified on your side, return **`403`** + `code: "EMAIL_NOT_VERIFIED"` (recommended), **or** return `success: true` with `email_verified: false` (app will block and show an error).

Providers like Google often verify email addresses, but the **source of truth** for “can use the app” should remain your `email_verified` flag if you require it for all users.

---

## 5. Resend verification email (`POST /auth/email/resend-verification`)

The app calls this endpoint (no auth header required) with:

**Request body**

```json
{
  "email": "user@example.com"
}
```

**Expected success**

```json
{
  "success": true,
  "message": "Verification email sent."
}
```

**Expected errors**

- Standard JSON error shape with `success: false` and `message` (and optional `errors` map), consistent with your other auth endpoints.

**Full URL in the app:** `https://stp.anmka.com/api/auth/email/resend-verification`  
If your path differs, tell the mobile team so `ApiEndpoints.resendEmailVerification` can be updated.

---

## 6. Email link / verification URL

The app does **not** need to handle the verification token inside the app for the minimal flow: the user taps the link in mail → your **web** (or universal link) verifies the token → user returns to the app and uses **Login**.

If you want **in-app** deep linking after verification (e.g. `anmka://verify?token=...`), that would be a separate task: add a route handler and optionally call a `POST /auth/email/verify` API from the app.

---

## 7. Summary checklist for backend

- [ ] Add `email_verified` on user JSON for register/login/social/`me`.
- [ ] Register: create user with `email_verified: false`, send email, return `email_verified: false`; ideally **no** tokens until verified.
- [ ] Login: reject unverified users with **`403` + `code: "EMAIL_NOT_VERIFIED"`** (and clear message), or rely on `email_verified: false` in a success payload (less ideal).
- [ ] Implement **`POST /api/auth/email/resend-verification`** with body `{ "email" }`.
- [ ] Ensure verification link sets `email_verified: true` in the database.

---

*Document generated for coordination between mobile (Flutter) and backend teams.*
