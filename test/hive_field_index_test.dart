import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static-source regression test for the `@HiveField`/`@HiveType` migration
/// invariant every domain model file states in its own doc comment: an
/// index/typeId, once assigned, may never be reused — a retired field must
/// stay as a tombstone comment (`// @HiveField(N) name — retired ...`)
/// rather than being deleted, so its index can't accidentally be handed to
/// a new field later. Hive itself won't catch that mistake — two fields
/// sharing an index just silently corrupt deserialization — so this test
/// parses the source directly and fails the build instead.
void main() {
  final domainFiles = [
    'lib/features/home/domain/day_entry.dart',
    'lib/features/home/domain/timeline_entry.dart',
    'lib/features/home/domain/timeline_amendment.dart',
    'lib/features/home/domain/daily_track.dart',
    'lib/features/home/domain/track_point.dart',
    'lib/features/home/domain/crew_member.dart',
    'lib/features/emergency/domain/emergency_contact.dart',
  ];

  // Matches both active (`@HiveField(4)`) and retired-but-tombstoned
  // (`// @HiveField(3) hasGpx — retired, ...`) declarations alike — the
  // invariant is that the index isn't reused, whether or not the field
  // whose comment mentions it is still live.
  final fieldPattern = RegExp(r'@HiveField\((\d+)\)');
  final typePattern = RegExp(r'@HiveType\(typeId:\s*(\d+)\)');

  for (final path in domainFiles) {
    test('$path declares no duplicate @HiveField index (active or retired)',
        () {
      final content = File(path).readAsStringSync();
      final seenAt = <int, int>{}; // index -> 1-based line of first use

      for (final match in fieldPattern.allMatches(content)) {
        final index = int.parse(match.group(1)!);
        final line = content.substring(0, match.start).split('\n').length;
        final firstLine = seenAt[index];
        expect(firstLine, isNull,
            reason: 'index $index appears at both line $firstLine and '
                'line $line in $path — a retired index must never be '
                "reused, see the file's MIGRATION INVARIANT comment");
        seenAt[index] = line;
      }
      expect(seenAt, isNotEmpty,
          reason: 'no @HiveField annotations found in $path — '
              'has the class been restructured?');
    });
  }

  test('@HiveType typeIds are globally unique across all domain models', () {
    final seenIn = <int, String>{};
    for (final path in domainFiles) {
      final content = File(path).readAsStringSync();
      for (final match in typePattern.allMatches(content)) {
        final typeId = int.parse(match.group(1)!);
        final existing = seenIn[typeId];
        expect(existing, isNull,
            reason: 'typeId $typeId is used by both $existing and $path — '
                'Hive typeIds must be unique across every model, not just '
                'within one file');
        seenIn[typeId] = path;
      }
    }
    expect(seenIn, isNotEmpty);
  });
}
