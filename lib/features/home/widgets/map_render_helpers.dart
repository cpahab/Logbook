import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/map_config.dart';
import 'day_detail_display_helpers.dart';

/// The tile layer shared by every map in the day-detail feature (inline
/// track map, inline positions-only map, and both fullscreen variants):
/// satellite/base URL switch, a larger keep-buffer so fewer tiles need a
/// fresh fetch right when a pan/zoom gesture ends, and a retry-on-next-view
/// fallback for tiles that failed to load once.
TileLayer mapTileLayer({required bool satelliteView}) => TileLayer(
      urlTemplate: satelliteView ? kSatelliteUrl : kBaseTileUrl,
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
    );

/// The attribution widget shared by every map in the day-detail feature.
RichAttributionWidget mapAttribution({required bool satelliteView}) =>
    RichAttributionWidget(attributions: [
      // MapTiler version (temporarily disabled, see map_config.dart):
      // TextSourceAttribution(kBaseAttributionLabel, onTap: () async {
      //   final uri = Uri.parse(kBaseAttributionUrl);
      //   if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      // }),
      // if (!satelliteView)
      //   TextSourceAttribution(kOsmAttributionLabel, onTap: () async {
      //     final uri = Uri.parse(kOsmAttributionUrl);
      //     if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      //   }),
      if (satelliteView)
        TextSourceAttribution(kSatelliteAttributionLabel, onTap: () async {
          final uri = Uri.parse(kSatelliteAttributionUrl);
          if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
        })
      else
        TextSourceAttribution(kBaseAttributionLabel, onTap: () async {
          final uri = Uri.parse(kBaseAttributionUrl);
          if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
        }),
    ]);

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
