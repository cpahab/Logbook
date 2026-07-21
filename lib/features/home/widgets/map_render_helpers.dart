import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;
import 'package:vector_tile_renderer/vector_tile_renderer.dart' show Logger;

import '../../../core/constants/map_config.dart';
import '../../../l10n/l10n_extension.dart';
import 'day_detail_display_helpers.dart';

/// The MapTiler vector style, loaded once and cached for the app's lifetime
/// — every [BaseVectorMapLayer] instance across every screen shares this
/// one Future so the style.json (and its sprite atlas) is fetched/parsed
/// exactly once per app run, not once per map widget or per rebuild.
Future<vmt.Style>? _baseStyleFuture;

Future<vmt.Style> _loadBaseStyle() => _baseStyleFuture ??= vmt.StyleReader(
      uri: kBaseVectorStyleUrl,
      apiKey: kMapTilerApiKey,
      logger: kDebugMode ? const Logger.console() : const Logger.noop(),
    ).read();

/// Clears the cached style load so the next [BaseVectorMapLayer] build
/// retries the network fetch — wired to the retry button after a failed load.
void resetBaseVectorStyleCache() => _baseStyleFuture = null;

/// The tile layer shared by every map in the app: satellite stays the
/// existing raster [TileLayer] (photographic imagery has no vector
/// equivalent, and this endpoint is already on MapTiler's cheap flat-rate
/// tile path); base switches to genuine vector tiles via
/// [BaseVectorMapLayer] — see kBaseVectorStyleUrl's comment in
/// map_config.dart for why.
Widget mapTileLayer({required bool satelliteView}) => satelliteView
    ? TileLayer(
        urlTemplate: kSatelliteUrl,
        userAgentPackageName: 'com.logbook.app',
        // Keep more of the surrounding tile grid loaded across a pan/zoom
        // transition so fewer tiles need a fresh fetch right when the
        // gesture ends (default is 2).
        keepBuffer: 4,
        // Default is `.none`, which never retries a tile that failed once
        // (transient network blip, tile-server rate limit) — it stays blank
        // until this whole map widget is rebuilt. Evicting once it scrolls
        // out of view lets it be re-fetched next time it's needed.
        evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
        errorTileCallback: kDebugMode
            ? (tile, error, stackTrace) =>
                debugPrint('[Map] tile ${tile.coordinates} failed to load: $error')
            : null,
        // Fade-in on arrival is TileLayer's default (tileDisplay:
        // TileDisplay.fadeIn()); this only overrides the tile that failed to
        // load, in place of a blank grey square.
        tileBuilder: (context, tileWidget, tile) => tile.loadError
            ? Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.map_outlined, size: 20),
              )
            : tileWidget,
      )
    : const BaseVectorMapLayer();

/// The vector base-map layer: loads the MapTiler vector style once (shared,
/// cached — see [_loadBaseStyle]) and renders it via vector_map_tiles.
/// StatefulWidget (not a plain function-built widget) so a failed load can
/// be retried locally without re-fetching for every other mounted instance.
class BaseVectorMapLayer extends StatefulWidget {
  const BaseVectorMapLayer({super.key});

  @override
  State<BaseVectorMapLayer> createState() => _BaseVectorMapLayerState();
}

class _BaseVectorMapLayerState extends State<BaseVectorMapLayer> {
  late Future<vmt.Style> _future = _loadBaseStyle();

  void _retry() => setState(() {
        resetBaseVectorStyleCache();
        _future = _loadBaseStyle();
      });

  @override
  Widget build(BuildContext context) => FutureBuilder<vmt.Style>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final style = snapshot.data!;
            return vmt.VectorTileLayer(
              theme: style.theme,
              sprites: style.sprites,
              tileProviders: style.providers,
              // This is OpenMapTiles-schema data (MapTiler's vector tiles
              // for this style), which — like most modern vector tile
              // sources — is designed around the "one zoom level sharper"
              // 512px-equivalent scale (the same convention already
              // confirmed for MapTiler's raster tiles): TileOffset.mapbox
              // is the package's own named offset for exactly this case.
              tileOffset: vmt.TileOffset.mapbox,
              // Renders each vector tile to a raster image once, then
              // composites images — smoother pan/zoom than redrawing vector
              // paths every frame. Doesn't affect what's fetched over the
              // network either way: both modes fetch the same vector .pbf
              // tile data, this only changes local rendering technique.
              layerMode: vmt.VectorTileLayerMode.raster,
              showTileDebugInfo: kDebugMode,
              // Default is 50MB. Vector tiles are small (a few tens of KB
              // each), so 50MB caps out at a fairly modest amount of cached
              // coastline — bumped to match the satellite layer's own
              // built-in disk cache default (BuiltInMapCachingProvider,
              // flutter_map's own — see map_config.dart's kSatelliteUrl
              // comment), so revisiting the same waters across sessions
              // needs fewer repeat network fetches either way.
              fileCacheMaximumSizeInBytes: 1000000000,
            );
          }
          if (snapshot.hasError) {
            if (kDebugMode) {
              debugPrint('[Map] base vector style failed to load: ${snapshot.error}');
            }
            return _BaseMapLoadError(onRetry: _retry);
          }
          // Waiting on the (usually one-time, already-cached) style.json
          // fetch — neutral placeholder instead of a flash of blank white.
          return const ColoredBox(color: Color(0xFFE3E9ED));
        },
      );
}

class _BaseMapLoadError extends StatelessWidget {
  const _BaseMapLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 28, color: cs.onSurfaceVariant),
            const SizedBox(height: 6),
            TextButton(onPressed: onRetry, child: Text(context.l10n.mapLoadRetry)),
          ],
        ),
      ),
    );
  }
}

/// The attribution widget shared by every map in the day-detail feature.
RichAttributionWidget mapAttribution({required bool satelliteView}) =>
    RichAttributionWidget(attributions: [
      TextSourceAttribution(kBaseAttributionLabel, onTap: () async {
        final uri = Uri.parse(kBaseAttributionUrl);
        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      }),
      if (!satelliteView)
        TextSourceAttribution(kOsmAttributionLabel, onTap: () async {
          final uri = Uri.parse(kOsmAttributionUrl);
          if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
        }),
      // OpenStreetMap/Esri version (temporarily disabled, see map_config.dart):
      // if (satelliteView)
      //   TextSourceAttribution(kSatelliteAttributionLabel, onTap: () async {
      //     final uri = Uri.parse(kSatelliteAttributionUrl);
      //     if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      //   })
      // else
      //   TextSourceAttribution(kBaseAttributionLabel, onTap: () async {
      //     final uri = Uri.parse(kBaseAttributionUrl);
      //     if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      //   }),
    ],
    showFlutterMapAttribution: false,);

/// The tap-to-inspect marker every day-detail map drops at [position],
/// showing [label] (if set) in a pill beside it, dismissed via [onDismiss].
Marker droppedMarker({
  required LatLng position,
  required String? label,
  required BuildContext context,
  required ColorScheme cs,
  required VoidCallback onDismiss,
}) =>
    Marker(
      point: position,
      width: 20,
      height: 20,
      alignment: Alignment.center,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.surface,
                border: Border.all(color: cs.primary, width: 2.5),
              ),
            ),
            if (label != null)
              Positioned(
                left: 16,
                top: 3,
                child: IgnorePointer(child: trackLabel(context, label, cs)),
              ),
          ],
        ),
      ),
    );

/// Small floating action button for a map's zoom/recenter controls.
/// [heroTagPrefix] keeps hero tags distinct between the inline map and its
/// fullscreen counterpart (both use the same icon set).
Widget mapZoomButton(
  IconData icon,
  VoidCallback onTap,
  ColorScheme cs, {
  required String heroTagPrefix,
}) =>
    FloatingActionButton.small(
      heroTag: '$heroTagPrefix${icon.codePoint}',
      onPressed: onTap,
      backgroundColor: cs.surfaceContainerLowest,
      foregroundColor: cs.primary,
      elevation: 2,
      child: Icon(icon, size: 18),
    );
