// Tile server URLs/attribution used by every map view in the app (day
// detail, tracks screen, PDF export). Exactly one of the two blocks below
// is active at a time — see each block's own comment.

// ===== MapTiler (production) =====
// Restored after being temporarily disabled for testing: the earlier
// tiles/openstreetmap 404 (fixed in f26d787) burned through the MapTiler
// free-tier quota, so the app ran on the free public OSM/Esri servers below
// while waiting for the quota to reset (2026-07-21). To disable MapTiler
// again, comment out this block and uncomment the "OpenStreetMap / Esri
// (testing)" block below.

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

const kBaseAttributionLabel = 'MapTiler';
const kBaseAttributionUrl = 'https://www.maptiler.com/copyright/';
const kOsmAttributionLabel = 'OpenStreetMap contributors';
const kOsmAttributionUrl = 'https://www.openstreetmap.org/copyright';
const kSatelliteAttributionLabel = 'MapTiler';
const kSatelliteAttributionUrl = 'https://www.maptiler.com/copyright/';

// ===== OpenStreetMap / Esri (testing) =====
// Free public tile servers, no API key required. Same providers this app
// used before the MapTiler migration. Disabled now that MapTiler is active
// again (see the comment on the block above).
//
// /// Public OSM raster tile server — flutter_map TileLayer urlTemplate.
// const kBaseTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
//
// /// Esri World Imagery satellite tiles — note z/y/x order, not z/x/y.
// const kSatelliteUrl =
//     'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
//
// const kBaseAttributionLabel = 'OpenStreetMap contributors';
// const kBaseAttributionUrl = 'https://www.openstreetmap.org/copyright';
// const kSatelliteAttributionLabel = 'Esri World Imagery';
// const kSatelliteAttributionUrl = 'https://www.esri.com';

/// Highest zoom the active tile server reliably has tiles for. Every map's
/// `MapOptions` must set this as `maxZoom` — without it, fitting the camera
/// to a near-zero-size bounding box (e.g. a track of two almost-identical
/// points) asks `CameraFit.bounds` to zoom in far past this, which requests
/// tiles that don't exist (a permanently blank/grey map) and can leave the
/// camera in a state no later `fitCamera`/`move` call recovers from.
const kMaxMapZoom = 19.0;
