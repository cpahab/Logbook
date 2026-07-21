// Tile server URLs/attribution used by every map view in the app (day
// detail, tracks screen, PDF export). Exactly one of the two blocks below
// is active at a time — see each block's own comment.

// ===== MapTiler (production) =====
// Restored after being temporarily disabled for testing: the tiles/
// openstreetmap 404 (fixed in f26d787) and, more importantly, the base
// layer silently defaulting to 512px tiles (4x the request cost of 256px,
// see kBaseTileUrl's own comment) burned through the MapTiler free-tier
// quota, so the app ran on the free public OSM/Esri servers below while
// waiting for the quota to reset (2026-07-21). To disable MapTiler again,
// comment out this block and uncomment the "OpenStreetMap / Esri (testing)"
// block below.

// Injected at build time via --dart-define=MAPTILER_KEY=...
// For local dev: add to .vscode/launch.json toolArgs (gitignored).
const kMapTilerApiKey = String.fromEnvironment(
  'MAPTILER_KEY',
  defaultValue: '',
);

/// MapTiler OpenStreetMap style, as raster tiles — flutter_map TileLayer
/// urlTemplate. No longer used by any live map (see kBaseVectorStyleUrl
/// below): kept, like the OpenStreetMap/Esri block further down, in case
/// vector rendering needs to be reverted. If reactivating, wire it back
/// into map_render_helpers.dart's mapTileLayer() in place of
/// BaseVectorMapLayer().
///
/// The explicit `256` size segment was load-bearing when this was live:
/// omitting it makes MapTiler default this endpoint to 512px tiles, which
/// its own pricing bills at 4 requests each vs. 1 for 256px — one of two
/// things that burned through the free-tier quota (see the block above).
/// The other, more fundamental problem this raster endpoint has — 256px
/// and 512px tiles at the same {z}/{x}/{y} cover *different* geographic
/// areas, not the same area at different resolutions (confirmed by
/// comparing downloaded tiles) — is why the fix wasn't just "always use
/// 256px" but switching to vector tiles entirely (see kBaseVectorStyleUrl).
const kBaseTileUrl =
    'https://api.maptiler.com/maps/openstreetmap/256/{z}/{x}/{y}.jpg?key=$kMapTilerApiKey';

/// MapTiler OpenStreetMap style, as a vector style — read by
/// vector_map_tiles' StyleReader (map_render_helpers.dart), not a
/// flutter_map TileLayer urlTemplate. This is the base map's live source:
/// StyleReader resolves this style.json's own `sources` entry (confirmed
/// live: a single "openmaptiles" source, `"type":"vector"`, pointing at
/// `tiles/v3-openmaptiles/tiles.json`) and fetches its vector (.pbf) tiles
/// directly from that /tiles/ endpoint — billed by MapTiler as flat-rate
/// Tile API requests (like kSatelliteUrl already is), not "Rendered maps"
/// usage, which is what kBaseTileUrl above was billed as and what burned
/// through the quota. Vector tiles have no tile-size/multiplier concept at
/// all, sidestepping that cost problem entirely rather than just picking a
/// cheaper raster size.
///
/// Same style ID as kBaseTileUrl ("openstreetmap"), fetched a different
/// way (confirmed both return HTTP 200), so the on-screen look matches what
/// it replaces. `{key}` is filled in by StyleReader's own apiKey parameter,
/// not string interpolation, hence the literal token here rather than
/// $kMapTilerApiKey.
const kBaseVectorStyleUrl =
    'https://api.maptiler.com/maps/openstreetmap/style.json?key={key}';

/// MapTiler satellite imagery (plain, no labels) — flutter_map TileLayer
/// urlTemplate. Raster, unchanged by the base layer's switch to vector
/// tiles: satellite imagery is a photo, not cartographic data, so it has no
/// vector equivalent — and this endpoint is already under /tiles/ (flat-rate
/// Tile API billing), so it was never implicated in the quota problem above.
///
/// Disk-cached automatically, with no config needed here: the plain
/// TileLayer this feeds (map_render_helpers.dart's mapTileLayer(), satellite
/// branch) defaults its tileProvider to NetworkTileProvider(), which itself
/// defaults to flutter_map's own BuiltInMapCachingProvider (1GB cap,
/// HTTP-header-driven freshness) whenever no cachingProvider is passed —
/// confirmed in flutter_map's own source, not just its docs.
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

/// Zoom ceiling for every map's `MapOptions.maxZoom`. Originally justified
/// by raster-tile-404 avoidance: fitting the camera to a near-zero-size
/// bounding box (e.g. a track of two almost-identical points) asks
/// `CameraFit.bounds` to zoom in far past what a raster tile server has,
/// leaving a permanently blank/grey map that no later `fitCamera`/`move`
/// call recovers from — still true for the satellite layer (kSatelliteUrl,
/// still raster). The vector base layer (kBaseVectorStyleUrl) doesn't have
/// this failure mode: vector_map_tiles overzooms past the style's native
/// max zoom (14, for this OpenMapTiles-schema source) by scaling up a
/// coarser tile rather than returning nothing. Kept at the same value as a
/// simple, already-tested zoom ceiling that works for both layer types.
const kMaxMapZoom = 19.0;
