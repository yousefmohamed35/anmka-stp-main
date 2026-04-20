/// Lesson ordering and lock rules shared by course details and lesson viewer.
///
/// Backend should normally set `is_locked` / `locked` on each lesson for the
/// authenticated student. Optional exam-gate fields are also recognized so the
/// app can still block access if the API sends those without `is_locked`.

bool lessonMapIsLocked(Map<String, dynamic> lesson) {
  if (lesson['is_locked'] == true || lesson['locked'] == true) return true;
  if (lesson['is_accessible'] == false) return true;
  if (lesson['can_access'] == false) return true;

  final blockExamId = lesson['blocking_exam_id'] ??
      lesson['required_exam_id'] ??
      lesson['unlock_after_exam_id'];
  if (blockExamId != null && blockExamId.toString().trim().isNotEmpty) {
    final met = lesson['required_exam_passed'] == true ||
        lesson['blocking_exam_passed'] == true ||
        lesson['exam_requirement_met'] == true ||
        lesson['after_exam_passed'] == true;
    if (!met) return true;
  }

  return false;
}

String lessonLockMessage(Map<String, dynamic> lesson) {
  for (final key in [
    'lock_message',
    'lock_reason',
    'locked_reason',
    'access_denied_message',
  ]) {
    final v = lesson[key]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return 'أكمل الامتحان المطلوب لفتح هذا الدرس';
}

/// Same ordering as [CourseDetailsScreen] curriculum / lessons tab.
List<Map<String, dynamic>> flattenLessonsFromCourse(
    Map<String, dynamic>? course) {
  final flat = <Map<String, dynamic>>[];
  if (course == null) return flat;

  final curriculum = course['curriculum'] as List?;
  final lessons = course['lessons'] as List?;

  if (curriculum != null && curriculum.isNotEmpty) {
    for (var item in curriculum) {
      if (item is! Map<String, dynamic>) continue;
      final nestedLessons = item['lessons'] as List?;
      final hasVideo = item['video'] != null;
      final hasYoutubeId =
          item['youtube_id'] != null || item['youtubeVideoId'] != null;
      final isTopic = nestedLessons != null || (!hasVideo && !hasYoutubeId);

      if (isTopic) {
        if (nestedLessons != null && nestedLessons.isNotEmpty) {
          for (var nestedLesson in nestedLessons) {
            if (nestedLesson is Map<String, dynamic>) {
              flat.add(nestedLesson);
            }
          }
        }
      } else {
        if (hasVideo || item['id'] != null || hasYoutubeId) {
          flat.add(item);
        }
      }
    }
  }

  if (flat.isEmpty && lessons != null && lessons.isNotEmpty) {
    for (var lesson in lessons) {
      if (lesson is Map<String, dynamic>) {
        flat.add(lesson);
      }
    }
  }

  return flat;
}

int? indexOfLessonInList(
  List<Map<String, dynamic>> lessons,
  Map<String, dynamic> lesson,
) {
  final id = lesson['id']?.toString();
  if (id == null || id.isEmpty) return null;
  final i = lessons.indexWhere((l) => l['id']?.toString() == id);
  return i >= 0 ? i : null;
}
