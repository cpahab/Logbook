import '../domain/day_entry.dart';

class HomeRepository {
  final List<DayEntry> _entries = [];

  List<DayEntry> get entries => List.unmodifiable(_entries);

  void addEntry(DateTime date) {
    _entries.add(DayEntry(date));
  }
}

// GLOBAL SINGLETON
final homeRepository = HomeRepository();
