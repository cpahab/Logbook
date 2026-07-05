// ===== MapTiler (production) =====
// Temporarily disabled for testing: switched to free public OSM/Esri
// servers below because the earlier tiles/openstreetmap 404 (fixed in
// f26d787) burned through the MapTiler free-tier quota, which now resets
// 2026-07-21. To restore MapTiler, delete the "OpenStreetMap / Esri
// (testing)" block below and uncomment this one.
//
// // Injected at build time via --dart-define=MAPTILER_KEY=...
// // For local dev: add to .vscode/launch.json toolArgs (gitignored).
// const kMapTilerApiKey = String.fromEnvironment(
//   'MAPTILER_KEY',
//   defaultValue: '',
// );
//
// /// MapTiler OpenStreetMap style — flutter_map TileLayer urlTemplate.
// ///
// /// Deliberately on the Maps API, not the Tiles API: there is no raster
// /// "openstreetmap" tileset under /tiles/ (confirmed via MapTiler's own
// /// "Tileset with this identifier does not exist" error) — /maps/openstreetmap
// /// is the only endpoint that serves this basemap as raster tiles. .jpg is
// /// MapTiler's own declared format for this style (see its tiles.json:
// /// "format":"jpg"), not just a same-endpoint tweak.
// const kBaseTileUrl =
//     'https://api.maptiler.com/maps/openstreetmap/{z}/{x}/{y}.jpg?key=$kMapTilerApiKey';
//
// /// MapTiler satellite imagery (plain, no labels) — flutter_map TileLayer urlTemplate.
// const kSatelliteUrl =
//     'https://api.maptiler.com/tiles/satellite-v2/{z}/{x}/{y}.jpg?key=$kMapTilerApiKey';
//
// const kBaseAttributionLabel = 'MapTiler';
// const kBaseAttributionUrl = 'https://www.maptiler.com/copyright/';
// const kOsmAttributionLabel = 'OpenStreetMap contributors';
// const kOsmAttributionUrl = 'https://www.openstreetmap.org/copyright';
// const kSatelliteAttributionLabel = 'MapTiler';
// const kSatelliteAttributionUrl = 'https://www.maptiler.com/copyright/';

// ===== OpenStreetMap / Esri (testing) =====
// Free public tile servers, no API key required. Same providers this app
// used before the MapTiler migration.

/// Public OSM raster tile server — flutter_map TileLayer urlTemplate.
const kBaseTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Esri World Imagery satellite tiles — note z/y/x order, not z/x/y.
const kSatelliteUrl =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

const kBaseAttributionLabel = 'OpenStreetMap contributors';
const kBaseAttributionUrl = 'https://www.openstreetmap.org/copyright';
const kSatelliteAttributionLabel = 'Esri World Imagery';
const kSatelliteAttributionUrl = 'https://www.esri.com';
