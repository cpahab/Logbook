import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'features/home/data/home_repository.dart';
import 'features/home/domain/day_entry.dart';
import 'features/home/domain/timeline_entry.dart';
import 'features/home/domain/daily_track.dart';
import 'features/home/domain/track_point.dart';

import 'app.dart'; // falls du eine eigene MyApp() Datei hast

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------------
  // HIVE INITIALIZATION
  // ------------------------------------------------------------
  await Hive.initFlutter();

  // Register all adapters
  Hive.registerAdapter(DayEntryAdapter());
  Hive.registerAdapter(TimelineEntryAdapter());
  Hive.registerAdapter(DailyTrackAdapter());
  Hive.registerAdapter(TrackPointAdapter());

  // ------------------------------------------------------------
  // REPOSITORY INITIALIZATION
  // ------------------------------------------------------------
  final repo = HomeRepository();
  await repo.init(); // ⭐ WICHTIG: Boxen öffnen + Daten laden

  // ------------------------------------------------------------
  // RUN APP
  // ------------------------------------------------------------
  runApp(
    ChangeNotifierProvider.value(
      value: repo,
      child: const MyApp(),
    ),
  );
}
