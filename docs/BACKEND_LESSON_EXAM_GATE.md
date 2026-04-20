# Backend: lock lessons until an exam is passed (exam ↔ lesson progression)

The Flutter student app **does not decide** which lesson is unlocked by itself. It reads **per-lesson flags** from the API and blocks navigation (course list, lesson list, and “next lesson” inside the player) when a lesson is locked.

After a student **submits** an exam successfully, the app calls **`GET` course details again** (silent refresh) so updated `is_locked` values appear without restarting the app.

---

## What the mobile client already understands

### Primary rule (recommended)

For each lesson in **`GET /courses/:courseId`** (or your equivalent “course details for student” payload), include:

| Field | Type | Meaning |
|--------|------|--------|
| `is_locked` | boolean | If `true`, the student **cannot open** this lesson and **cannot** move to it as the “next” lesson. |
| `locked` | boolean | Same as `is_locked` (alternate key supported by the app). |

Optional UX fields (any one is shown in a snackbar when the user taps a locked lesson):

| Field | Type | Meaning |
|--------|------|--------|
| `lock_message` | string | Human-readable reason (e.g. “Pass the chapter 1 exam to continue”). |
| `lock_reason` | string | Same purpose, alternate key. |

### Optional explicit exam-gate fields

If you prefer to express the gate without setting `is_locked` yet, the app **also** treats a lesson as locked when **all** of the following hold:

- One of: `blocking_exam_id`, `required_exam_id`, or `unlock_after_exam_id` is a non-empty string, **and**
- None of: `required_exam_passed`, `blocking_exam_passed`, `exam_requirement_met`, `after_exam_passed` is `true`.

**Recommendation:** still set `is_locked` on the API so the rule is unambiguous and matches admin expectations.

---

## Backend responsibilities

1. **Model**  
   - Associate each “gate” with an exam (e.g. “lessons after L3 require exam E1”).  
   - Store per-user (per enrollment) whether that exam was **passed** (`is_passed` / score ≥ passing score).

2. **Course details response**  
   - When building the curriculum / `lessons` array for the **authenticated** student, set `is_locked: true` on every lesson that must not be accessed until the required exam is passed.  
   - Set `is_locked: false` (and optional `lock_message` cleared) once the exam is passed.

3. **Exam submit**  
   - `POST …/exams/:id/submit` (or your route) should persist the attempt and pass/fail.  
   - The next **`GET` course details** must reflect new locks (e.g. unlock lesson 4 after passing exam for lesson 3 block).

4. **Optional hardening**  
   - If the client calls **`GET /courses/:courseId/lessons/:lessonId`** or content endpoints for a locked lesson, return **403** with a clear JSON `message` so the server never leaks video URLs for locked items.

---

## Example (conceptual)

After the student passes exam `exam_mid_01`, lessons `les_010`–`les_020` flip from `is_locked: true` to `false`. Lessons `les_021+` stay locked until `exam_final_01` is passed.

```json
{
  "id": "les_015",
  "title": "Advanced topic",
  "is_locked": false,
  "blocking_exam_id": "exam_mid_01",
  "required_exam_passed": true
}
```

```json
{
  "id": "les_022",
  "title": "Certificate prep",
  "is_locked": true,
  "lock_message": "Complete the final exam to unlock this lesson."
}
```

---

## Related mobile code (for your reference)

- `lib/utils/lesson_access.dart` — `lessonMapIsLocked`, `flattenLessonsFromCourse`  
- `lib/screens/secondary/course_details_screen.dart` — lesson list, exam flow, refresh after exam  
- `lib/screens/secondary/lesson_viewer_screen.dart` — “next / previous” respects the same lock rules  

---

## Exam list endpoint

The app already loads course exams (e.g. `GET /courses/:courseId/exams`) for the Exams tab. Ensure each exam includes student-specific fields such as `is_passed`, `can_start`, `attempts_used`, so the UI matches the same rules you use for lesson locking.
