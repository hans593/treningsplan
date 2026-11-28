// Kart over GPS-ruta fra klokka. Norge: Kartverkets topografiske kart (med høydekurver).
// Utenfor Norge: OpenStreetMap. Ruta er farget etter pulssone.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models.dart';
import 'watch_details.dart' show zoneColors;

const _kartverket = 'https://cache.kartverket.no/v1/wmts/1.0.0/topo/default/webmercator/{z}/{y}/{x}.png';
const _kartverketReserve = 'https://cache.kartverket.no/v1/service?layer=topo&style=default'
    '&tilematrixset=webmercator&Service=WMTS&Request=GetTile&Version=1.0.0&Format=image/png'
    '&TileMatrix={z}&TileCol={x}&TileRow={y}';
const _osm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

bool _inNorway(LatLng p) => p.latitude > 57.5 && p.latitude < 71.5 && p.longitude > 4 && p.longitude < 31.5;

/// Delstrekninger med samme pulssone, så ruta kan fargelegges.
List<Polyline> routePolylines(WatchData d) {
  final out = <Polyline>[];
  for (final seg in d.route) {
    if (seg.length < 2) continue;
    var cur = <LatLng>[LatLng(seg[0][0].toDouble(), seg[0][1].toDouble())];
    var zone = seg[0].length > 2 ? seg[0][2].toInt() : -1;
    for (var i = 1; i < seg.length; i++) {
      final p = LatLng(seg[i][0].toDouble(), seg[i][1].toDouble());
      final z = seg[i].length > 2 ? seg[i][2].toInt() : -1;
      cur.add(p);
      if (z != zone || i == seg.length - 1) {
        out.add(Polyline(
          points: cur,
          strokeWidth: 5,
          color: zone >= 0 && zone < 5 ? zoneColors[zone] : const Color(0xFF2E5E4E),
          borderStrokeWidth: 1.5,
          borderColor: Colors.white,
        ));
        cur = [p];
        zone = z;
      }
    }
  }
  return out;
}

class RouteMap extends StatelessWidget {
  final WatchData data;
  final bool interactive;
  const RouteMap(this.data, {super.key, this.interactive = false});

  @override
  Widget build(BuildContext context) {
    final all = [
      for (final seg in data.route)
        for (final p in seg) LatLng(p[0].toDouble(), p[1].toDouble())
    ];
    if (all.length < 2) return const SizedBox.shrink();
    final norway = _inNorway(all.first);
    final starts = [
      for (final seg in data.route)
        if (seg.isNotEmpty) LatLng(seg.first[0].toDouble(), seg.first[1].toDouble())
    ];
    final last = data.route.lastWhere((s) => s.isNotEmpty).last;
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(all),
          padding: const EdgeInsets.all(28),
          maxZoom: 16,
        ),
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: norway ? _kartverket : _osm,
          fallbackUrl: norway ? _kartverketReserve : null,
          userAgentPackageName: 'no.treningsplan.treningsplan',
          maxNativeZoom: norway ? 18 : 19,
        ),
        PolylineLayer(polylines: routePolylines(data)),
        MarkerLayer(markers: [
          for (final s in starts)
            Marker(
              point: s,
              width: 18,
              height: 18,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D4F),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
          Marker(
            point: LatLng(last[0].toDouble(), last[1].toDouble()),
            width: 30,
            height: 30,
            alignment: Alignment.topCenter,
            child: const Icon(Icons.flag, color: Color(0xFF1B1B1B), size: 28),
          ),
        ]),
        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            color: Colors.white.withValues(alpha: 0.8),
            child: Text(norway ? '© Kartverket' : '© OpenStreetMap',
                style: const TextStyle(fontSize: 11, color: Colors.black87)),
          ),
        ),
      ],
    );
  }
}

/// Kartet i kortet: trykk for fullskjerm.
class RouteMapCard extends StatelessWidget {
  final WatchData data;
  const RouteMapCard(this.data, {super.key});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 240,
          child: Stack(children: [
            Positioned.fill(child: RouteMap(data)),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text('${data.activity} · ${fmtUkedag(data.start)}')),
                        body: RouteMap(data, interactive: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.open_in_full, size: 18),
              ),
            ),
          ]),
        ),
      );
}
