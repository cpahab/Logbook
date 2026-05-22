import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/router.dart';
import 'features/home/data/home_repository.dart';

void main() {
  runApp(
    ChangeNotifierProvider<HomeRepository>(
      create: (_) => HomeRepository(),
      child: const MyApp(),
)
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Logbook',
      routerConfig: appRouter,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
    );
  }
}
