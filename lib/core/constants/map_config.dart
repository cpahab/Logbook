// Injected at build time via --dart-define=MAPTILER_KEY=...
// For local dev: add to .vscode/launch.json toolArgs (gitignored).
const kMapTilerApiKey = String.fromEnvironment(
  'MAPTILER_KEY',
  defaultValue: '',
);

/// MapTiler OpenStreetMap style — flutter_map TileLayer urlTemplate.
const kBaseTileUrl =
    'https://api.maptiler.com/tiles/openstreetmap/{z}/{x}/{y}.jpg?key=$kMapTilerApiKey';

/// MapTiler satellite imagery (plain, no labels) — flutter_map TileLayer urlTemplate.
const kSatelliteUrl =
    'https://api.maptiler.com/tiles/satellite-v2/{z}/{x}/{y}.jpg?key=$kMapTilerApiKey';
