const kMapTilerApiKey = 'vp4ZSDwE0yUaVvFJOs4G';

/// MapTiler OpenStreetMap style — flutter_map TileLayer urlTemplate.
const kBaseTileUrl =
    'https://api.maptiler.com/maps/openstreetmap/{z}/{x}/{y}.png?key=$kMapTilerApiKey';

/// MapTiler satellite imagery (plain, no labels) — flutter_map TileLayer urlTemplate.
const kSatelliteUrl =
    'https://api.maptiler.com/tiles/satellite-v2/{z}/{x}/{y}.jpg?key=$kMapTilerApiKey';
