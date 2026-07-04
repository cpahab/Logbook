// Injected at build time via --dart-define=MAPTILER_KEY=...
// For local dev: add to .vscode/launch.json toolArgs (gitignored).
const kMapTilerApiKey = String.fromEnvironment(
  'MAPTILER_KEY',
  defaultValue: '',
);

/// MapTiler OpenStreetMap style — flutter_map TileLayer urlTemplate.
///
/// Deliberately on the Maps API, not the Tiles API: there is no raster
/// "openstreetmap" tileset under /tiles/ (confirmed via MapTiler's own
/// "Tileset with this identifier does not exist" error) — /maps/openstreetmap
/// is the only endpoint that serves this basemap as raster tiles. .jpg is
/// MapTiler's own declared format for this style (see its tiles.json:
/// "format":"jpg"), not just a same-endpoint tweak.
const kBaseTileUrl =
    'https://api.maptiler.com/maps/openstreetmap/{z}/{x}/{y}.jpg?key=$kMapTilerApiKey';

/// MapTiler satellite imagery (plain, no labels) — flutter_map TileLayer urlTemplate.
const kSatelliteUrl =
    'https://api.maptiler.com/tiles/satellite-v2/{z}/{x}/{y}.jpg?key=$kMapTilerApiKey';
