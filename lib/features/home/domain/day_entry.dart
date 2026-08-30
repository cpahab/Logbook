import 'package:hive/hive.dart';
import 'timeline_entry.dart';
import 'track_point.dart';
import 'crew_member.dart';

part 'day_entry.g.dart';

// MIGRATION INVARIANT: Never change an existing @HiveField index or typeId.
// Retired indices must stay as tombstone comments so they are never reused.
// New fields must get the next unused index and be nullable so old objects deserialise safely.
/// One calendar day's journal entry — the app's core data unit. Holds the
/// day's timeline (see [TimelineEntry]), raw GPS track, crew aboard, and
/// free-text notes. Synced to Firestore by FirestoreService (per-field merge
/// writes; see saveEntry's doc comment there for the sync strategy).
@HiveType(typeId: 11)
class DayEntry extends HiveObject {
  @HiveField(0)
  DateTime date;

  @HiveField(1)
  List<TimelineEntry> timeline;

  @HiveField(2)
  List<TrackPoint> track;

  // @HiveField(3) hasGpx — retired, do not reuse index

  // Null/empty convention for this and every other nullable free-text field
  // below (toHarbor, notes, freeText, ...): null means "never set / cleared
  // by the user"; an empty string is never persisted — every save site trims
  // input and stores null instead (see day_detail_screen.dart's edit
  // handlers). Treat null and "" as equivalent when reading.
  @HiveField(4)
  String? fromHarbor;

  @HiveField(5)
  String? toHarbor;

  // Statistics — written during GPX import. On-screen stats normally come
  // live from raw track points via computeDailyStats(); distanceNm is the
  // one exception, read back as a fallback when a day has no live track to
  // recompute from (see home_screen.dart's sailing-days/total-distance
  // aggregation). The rest exist only for Firestore sync/backup
  // compatibility — do not rely on them for display.
  @HiveField(6)
  double distanceNm;

  @HiveField(7)
  int totalDurationSeconds;

  @HiveField(8)
  int movingDurationSeconds;

  @HiveField(9)
  double avgSpeedKnots;

  @HiveField(10)
  double maxSpeedKnots;

  // @HiveField(11) participants      — retired, do not reuse index
  // @HiveField(12) controlled        — retired, do not reuse index
  // @HiveField(13) participantsList  — retired, do not reuse index
  // @HiveField(14) checkedItems      — retired, do not reuse index

  @HiveField(15)
  String? notes;

  @HiveField(16)
  int? oilLevel; // 0–100

  @HiveField(17)
  int? fuelLevel; // 0–100

  @HiveField(18)
  List<CrewMember> crew;

  @HiveField(19)
  String? freeText;

  /// Retractable keel position. true = keel down (sailing), false = keel up
  /// (shallow water / harbour). null = not yet recorded.
  @HiveField(20)
  bool? keelDown;

  /// Firebase Storage paths for photos attached to this day (e.g.
  /// "photos/2026-06-16/1718440000000.jpg"). Local cache is managed by
  /// PhotoService.
  @HiveField(21)
  List<String> photos;

  /// Set once when the day entry is first created. Never overwritten.
  @HiveField(22)
  DateTime? createdAt;

  /// Updated on every save. Reflects the last time any field on this entry changed.
  @HiveField(23)
  DateTime? updatedAt;

  /// Set when this whole day was deleted — a tombstone, not a physical
  /// removal, so the deletion itself durably syncs (see FirestoreService's
  /// deleteEntry doc comment). A locally-deleted entry is removed from
  /// HomeRepository's in-memory/Hive state entirely; this field only ever
  /// exists on an *incoming* remote entry that needs to be interpreted as
  /// "remove this locally too."
  @HiveField(24)
  DateTime? deletedAt;

  /// Set when this day's GPX track (but not the day entry itself) was
  /// deleted — same tombstone rationale as [deletedAt], scoped to just the
  /// track. GPX tracks live in Firebase Storage, not Firestore, so this
  /// field on the (Firestore-synced) entry is what makes track deletion
  /// durable and lets other devices learn about it.
  @HiveField(25)
  DateTime? trackDeletedAt;

  DayEntry({
    required this.date,
    this.timeline = const [],
    this.track = const [],
    this.fromHarbor,
    this.toHarbor,
    this.distanceNm = 0.0,
    this.totalDurationSeconds = 0,
    this.movingDurationSeconds = 0,
    this.avgSpeedKnots = 0.0,
    this.maxSpeedKnots = 0.0,
    this.notes,
    this.oilLevel,
    this.fuelLevel,
    List<CrewMember>? crew,
    this.freeText,
    this.keelDown,
    List<String>? photos,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.trackDeletedAt,
  })  : crew = crew ?? <CrewMember>[],
        photos = photos ?? <String>[];

  // Convenience getters
  Duration get totalDuration => Duration(seconds: totalDurationSeconds);
  Duration get movingDuration => Duration(seconds: movingDurationSeconds);

  set totalDuration(Duration d) => totalDurationSeconds = d.inSeconds;
  set movingDuration(Duration d) => movingDurationSeconds = d.inSeconds;
}
