import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'features/home/data/home_repository.dart';
import 'features/home/domain/day_entry.dart';
import 'features/home/domain/timeline_entry.dart';
import 'features/home/domain/daily_track.dart';
import 'features/home/domain/track_point.dart';
import 'features/settings/domain/theme_provider.dart';

import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  Hive.registerAdapter(DayEntryAdapter());
  Hive.registerAdapter(TimelineEntryAdapter());
  Hive.registerAdapter(DailyTrackAdapter());
  Hive.registerAdapter(TrackPointAdapter());

  final repo = HomeRepository();
  await repo.init();

  final themeProvider = ThemeProvider();
  await themeProvider.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: repo),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: const MyApp(),
    ),
  );
}
