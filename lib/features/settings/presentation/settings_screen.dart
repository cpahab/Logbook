import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/services/firestore_service.dart';
import '../../../core/services/storage_service.dart';
import '../../home/data/home_repository.dart';
import '../domain/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _titleController;
  late TextEditingController _weatherController;
  final TextEditingController _codeController = TextEditingController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<ThemeProvider>();
    _titleController = TextEditingController(text: p.logbuchTitle);
    _weatherController = TextEditingController(text: p.weatherUrl);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _weatherController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String _formatCode(String code) {
    if (code.length == 8) return '${code.substring(0, 4)}-${code.substring(4)}';
    return code;
  }

  Future<void> _forceSync() async {
    setState(() => _syncing = true);
    try {
      await context.read<HomeRepository>().forceSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synchronisierung abgeschlossen.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _connectCode() async {
    final rawCode = _codeController.text;
    final code = rawCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (code.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ungültiger Code.')),
      );
      return;
    }

    // Read providers before the async gap.
    final themeProvider = context.read<ThemeProvider>();
    final repo = context.read<HomeRepository>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logbuch verbinden'),
        content: Text(
          'Dieses Gerät wird mit dem Logbuch "$code" verbunden. '
          'Lokale und entfernte Einträge werden zusammengeführt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verbinden'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    themeProvider.setLogbookCode(code);
    _codeController.clear();
    if (mounted) FocusScope.of(context).unfocus();

    setState(() => _syncing = true);
    try {
      await repo.reattachAndSync(
        FirestoreService(installationId: code),
        StorageService(installationId: code),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verbunden und synchronisiert.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;
    final code = themeProvider.logbookCode;

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionLabel(context, 'Allgemein'),
          const SizedBox(height: 8),
          Card(
            color: scheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Titel',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          )),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      hintText: 'Logbuch',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    textInputAction: TextInputAction.done,
                    onChanged: (v) => themeProvider.setLogbuchTitle(v),
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel(context, 'Wetter'),
          const SizedBox(height: 8),
          Card(
            color: scheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Wetter-URL',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          )),
                  const SizedBox(height: 4),
                  Text(
                    'Wird beim Tippen auf "Wetter" in der Navigation geöffnet.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _weatherController,
                    decoration: InputDecoration(
                      hintText: 'https://www.windy.com',
                      prefixIcon: const Icon(Icons.language_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    onChanged: (v) => themeProvider.setWeatherUrl(v),
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel(context, 'Erscheinungsbild'),
          const SizedBox(height: 8),
          Card(
            color: scheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Design',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          )),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto_outlined),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Hell'),
                          icon: Icon(Icons.light_mode_outlined),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dunkel'),
                          icon: Icon(Icons.dark_mode_outlined),
                        ),
                      ],
                      selected: {themeProvider.themeMode},
                      onSelectionChanged: (selection) =>
                          themeProvider.setThemeMode(selection.first),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel(context, 'Cloud-Sync'),
          const SizedBox(height: 8),
          Card(
            color: scheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Logbuch-Code',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Gib diesen Code auf einem anderen Gerät ein, um dasselbe Logbuch zu verwenden.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _formatCode(code),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: scheme.onPrimaryContainer,
                              letterSpacing: 6,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: _formatCode(code)));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Code kopiert.')),
                          );
                        },
                        icon: const Icon(Icons.copy_outlined),
                        tooltip: 'Kopieren',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Mit anderem Logbuch verbinden',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Gib den Code eines anderen Geräts ein.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          decoration: InputDecoration(
                            hintText: 'XXXX-XXXX',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _connectCode(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _syncing ? null : _connectCode,
                        child: const Text('Verbinden'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: _syncing ? null : _forceSync,
                      child: _syncing
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.sync_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Jetzt synchronisieren'),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
