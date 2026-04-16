# Backend updates: chat images and captions

The mobile app sends **text-only** messages as before (`JSON` body) and sends **messages that include an image** (image-only or image + caption) as **`multipart/form-data`** on the same endpoint. List/detail responses and real-time payloads should expose a stable **image URL or path** the client can resolve with the existing media base URL helper.

## 1. `POST /api/chat/conversations/:conversationId/messages`

### Text-only (unchanged)

- **Content-Type:** `application/json`
- **Body:** `{ "body": "message text" }`

### Image (optional caption)

- **Content-Type:** `multipart/form-data`
- **Fields:**
  - `body` (string, optional): Caption; may be empty or omitted when the backend allows image-only messages. The app always sends `body` in multipart (possibly empty string).
- **Files:**
  - `image` (file, required for this mode): One image (e.g. JPEG/PNG/WebP).

**Validation**

- Reject the request if there is **no** `image` file **and** `body` is empty (after trim).
- Enforce max file size and allowed MIME types server-side (recommend documenting limits in API docs).

**Response (`success: true`, `data`)**

Return the created message object in the same shape as for text messages, plus image metadata, for example:

- `id`, `conversationId` (or equivalent), `senderId`, `createdAt` / `created_at`
- `body` — caption string (empty string if image-only)
- **One** of the following (pick one name and use it consistently; the app currently checks, in order: `imageUrl`, `image`, `attachmentUrl`, `mediaUrl`, `imagePath`):
  - Preferred: `imageUrl` — either a full `https://...` URL or a path the app can pass to its image resolver (e.g. `/api/uploads/...`).

Store the file in your existing uploads/CDN pipeline and persist the public or API-relative URL/path on the message row.

## 2. `GET /api/chat/conversations/:conversationId/messages` (and pagination)

Each message in the list should include the same fields as `POST` returns so image messages render after refresh:

- `body`
- Image field (`imageUrl` recommended), or `null`/omit when the message is text-only.

## 3. WebSocket / Socket.IO (`chat:message` or equivalent)

When a message is created (REST or otherwise), broadcast the **same JSON shape** as the REST `data` payload, including `imageUrl` (or your chosen field) for image messages, so clients update in real time without polling.

## 4. Database

- Add nullable **image URL/path** (or attachment id FK) column on the chat message table, e.g. `image_url` or `attachment_id`.
- Optional: `message_type` enum (`text`, `image`, `image_text`) if you want explicit typing; not required if type is implied by `imageUrl` being non-null.

## 5. Read receipts / other chat routes

- `PATCH /api/chat/messages/:messageId/read` — no change required unless your implementation assumes only text; ensure it works for image messages the same as text.

## Summary

| Concern | Action |
|--------|--------|
| Multipart on existing messages URL | Accept `multipart/form-data` with field `body` + file field `image` |
| JSON text-only | Keep current `{ "body" }` behavior |
| Responses + WS | Include one canonical image URL/path field (prefer `imageUrl`) |
| DB | Persist image reference per message |
