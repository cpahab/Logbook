# 6. Maps — Required Change Before Any App Store Submission

> This must be addressed regardless of which other upgrades are pursued.
> Both current tile providers violate their terms of service for published apps.

**Estimated effort:** 2 days
**Dependencies:** None — do this first
**Ready-to-paste prompt:** [Appendix A1](Implementation-Prompts#a1--map-tile-provider-switch-maptiler--esri)

---

## Current situation

The app uses two tile sources, called in **five places** (`tracks_screen.dart` ×2, `day_detail_screen.dart` ×2, `pdf_exporter.dart` ×1):

| Tile source | Problem |
|-------------|---------|
| `tile.openstreetmap.org` | OSM's own servers are explicitly off-limits for distributed apps. Their policy states that heavy use (including app distribution) is forbidden without prior permission from the OSM Operations Working Group. |
| `server.arcgisonline.com` (Esri) | The ArcGIS Living Atlas World Imagery basemap requires an Esri Developer account and an API key for production use, even on the free tier. Currently called with no credentials. |

---

## Recommended solution: MapTiler

MapTiler is an OSM-compatible tile CDN that is **drop-in compatible with `flutter_map`**.
It is specifically recommended for this app because it offers a **nautical chart map style**
(depth contours, buoys, traffic separation zones, port markers) — directly relevant to sailors.

| MapTiler tier | Tile requests/month | Cost |
|--------------|---------------------|------|
| Free | 100,000 | €0 |
| Pay-as-you-go | Unlimited | €0.003 per 1,000 above free tier |
| At 500 users (est.) | ~50,000 requests | €0 — within free tier |
| At 2,000 users (est.) | ~200,000 requests | ~€0.30/month |

For the Esri satellite layer, the existing URL continues to work — just add an API key from
the free ArcGIS Developer tier (2 million tile requests/month free).

---

## Code change

The change is a URL swap in five locations plus a new constants file.

```dart
// lib/core/constants/map_config.dart
const kMapTilerApiKey = 'YOUR_MAPTILER_API_KEY';
const kBaseTileUrl =
    'https://api.maptiler.com/maps/nautical/{z}/{x}/{y}.png?key=$kMapTilerApiKey';
const kSatelliteUrl =
    'https://server.arcgisonline.com/.../tile/{z}/{y}/{x}?token=$kEsriKey';
```

Files to update:
- `lib/features/tracks/presentation/tracks_screen.dart` (×2)
- `lib/features/home/presentation/day_detail_screen.dart` (×2)
- `lib/features/home/utils/pdf_exporter.dart` (×1)
- Update `RichAttributionWidget` in both map widgets to credit MapTiler

The `flutter_map` package and `latlong2` do not need to change. No provider migration required.

---

## MapTiler vs Mapbox summary

| | MapTiler | Mapbox |
|--|----------|--------|
| Free tier | 100,000 map loads/month | 50,000 map loads/month |
| flutter_map compatible | Yes — standard XYZ tile URLs, drop-in | No — requires separate `mapbox_maps_flutter` SDK |
| Nautical charts | Yes, built-in NAUTICAL style | No native nautical style |
| OSM base | Yes | Originally OSM, now proprietary |
| Effort to integrate | URL swap | SDK replacement |

**MapTiler wins** for this app: nautical style, drop-in compatibility, 2× more generous free tier.
