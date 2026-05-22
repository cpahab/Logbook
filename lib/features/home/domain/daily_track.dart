import 'package:hive/hive.dart';
import 'track_point.dart';

part 'daily_track.g.dart';

@HiveType(typeId: 3)
class DailyTrack extends HiveObject {
  @HiveField(0)
  DateTime day; // normalized date (yyyy-mm-dd)

  @HiveField(1)
  String fileName; // original GPX file name

  @HiveField(2)
  List<TrackPoint> points; // full GPX track for that day

  DailyTrack({
    required this.day,
    required this.fileName,
    required this.points,
  });
}
