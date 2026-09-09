import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

class RouteOption {
  final List<List<double>> coordinates;
  final double distanceMeters;
  final double durationSeconds;

  RouteOption({
    required this.coordinates,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  double get distanceKm => distanceMeters / 1000;

  int get durationMinutes => (durationSeconds / 60).round();
}

class RouteService {
  static const String _baseUrl =
      'https://router.project-osrm.org';

  // ------------------------------------------------------------
  // PUBLIC METHOD
  // ------------------------------------------------------------

  static Future<List<RouteOption>> getRoutes({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    print('------------------------------------------');
    print('HYDROPULSE ROUTING');
    print('Start: $startLat, $startLng');
    print('End:   $endLat, $endLng');
    print('------------------------------------------');

    // First try OSRM's own alternatives.
    final normalRoutes = await _getOsrmRoutes(
      startLat: startLat,
      startLng: startLng,
      endLat: endLat,
      endLng: endLng,
      alternatives: true,
    );

    print(
      'OSRM normal routes received: ${normalRoutes.length}',
    );

    // If OSRM already gives 3 routes, use them.
    if (normalRoutes.length >= 3) {
      return normalRoutes.take(3).toList();
    }

    // Start with whatever OSRM gave us.
    final List<RouteOption> allRoutes = [
      ...normalRoutes,
    ];

    // ----------------------------------------------------------
    // FALLBACK
    //
    // OSRM may return only one route.
    // We then create different waypoint-based journeys.
    // The routing is still performed by OSRM, so the paths
    // follow actual roads.
    // ----------------------------------------------------------

    final fallbackWaypoints = _createWaypointCandidates(
      startLat,
      startLng,
      endLat,
      endLng,
    );

    for (final waypoint in fallbackWaypoints) {
      if (allRoutes.length >= 3) {
        break;
      }

      try {
        final waypointRoutes = await _getRouteThroughWaypoint(
          startLat: startLat,
          startLng: startLng,
          waypointLat: waypoint[0],
          waypointLng: waypoint[1],
          endLat: endLat,
          endLng: endLng,
        );

        for (final route in waypointRoutes) {
          if (_isDifferentRoute(route, allRoutes)) {
            allRoutes.add(route);

            print(
              'Added fallback route ${allRoutes.length}: '
              '${route.distanceKm.toStringAsFixed(2)} km',
            );
          }

          if (allRoutes.length >= 3) {
            break;
          }
        }
      } catch (e) {
        print(
          'Waypoint route failed: $e',
        );
      }
    }

    print(
      'FINAL ROUTES RETURNED: ${allRoutes.length}',
    );

    for (int i = 0; i < allRoutes.length; i++) {
      print(
        'Route ${i + 1}: '
        '${allRoutes[i].distanceKm.toStringAsFixed(2)} km, '
        '${allRoutes[i].durationMinutes} min',
      );
    }

    print('------------------------------------------');

    return allRoutes.take(3).toList();
  }

  // ------------------------------------------------------------
  // NORMAL OSRM ROUTING
  // ------------------------------------------------------------

  static Future<List<RouteOption>> _getOsrmRoutes({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    bool alternatives = false,
  }) async {
    final url = Uri.parse(
      '$_baseUrl/route/v1/driving/'
      '$startLng,$startLat;'
      '$endLng,$endLat'
      '?alternatives=$alternatives'
      '&steps=true'
      '&overview=full'
      '&geometries=geojson',
    );

    print('OSRM URL: $url');

    final response = await http.get(
      url,
      headers: {
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Routing service failed: ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body);

    if (data['code'] != 'Ok') {
      throw Exception(
        'No route found: ${data['code']}',
      );
    }

    final routes = data['routes'] as List;

    return routes.map<RouteOption>((route) {
      final geometry = route['geometry'];

      final rawCoordinates =
          geometry['coordinates'] as List;

      final coordinates =
          rawCoordinates.map<List<double>>((point) {
        return [
          (point[1] as num).toDouble(),
          (point[0] as num).toDouble(),
        ];
      }).toList();

      return RouteOption(
        coordinates: coordinates,
        distanceMeters:
            (route['distance'] as num).toDouble(),
        durationSeconds:
            (route['duration'] as num).toDouble(),
      );
    }).toList();
  }

  // ------------------------------------------------------------
  // ROUTE THROUGH A WAYPOINT
  // ------------------------------------------------------------

  static Future<List<RouteOption>>
      _getRouteThroughWaypoint({
    required double startLat,
    required double startLng,
    required double waypointLat,
    required double waypointLng,
    required double endLat,
    required double endLng,
  }) async {
    final url = Uri.parse(
      '$_baseUrl/route/v1/driving/'
      '$startLng,$startLat;'
      '$waypointLng,$waypointLat;'
      '$endLng,$endLat'
      '?alternatives=false'
      '&steps=true'
      '&overview=full'
      '&geometries=geojson',
    );

    final response = await http.get(
      url,
      headers: {
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Waypoint routing failed: ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body);

    if (data['code'] != 'Ok') {
      throw Exception(
        'Waypoint route unavailable',
      );
    }

    final routes = data['routes'] as List;

    return routes.map<RouteOption>((route) {
      final geometry = route['geometry'];

      final rawCoordinates =
          geometry['coordinates'] as List;

      final coordinates =
          rawCoordinates.map<List<double>>((point) {
        return [
          (point[1] as num).toDouble(),
          (point[0] as num).toDouble(),
        ];
      }).toList();

      return RouteOption(
        coordinates: coordinates,
        distanceMeters:
            (route['distance'] as num).toDouble(),
        durationSeconds:
            (route['duration'] as num).toDouble(),
      );
    }).toList();
  }

  // ------------------------------------------------------------
  // CREATE DIFFERENT WAYPOINTS
  // ------------------------------------------------------------

  static List<List<double>> _createWaypointCandidates(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    final midLat =
        (startLat + endLat) / 2;

    final midLng =
        (startLng + endLng) / 2;

    final deltaLat =
        endLat - startLat;

    final deltaLng =
        endLng - startLng;

    final length =
        sqrt(
          deltaLat * deltaLat +
              deltaLng * deltaLng,
        );

    // Avoid division by zero.
    if (length == 0) {
      return [];
    }

    // Perpendicular direction.
    final perpLat =
        -deltaLng / length;

    final perpLng =
        deltaLat / length;

    // Scale based on trip length.
    final offset =
        max(
          0.0015,
          min(
            0.01,
            length * 0.35,
          ),
        );

    return [
      [
        midLat + perpLat * offset,
        midLng + perpLng * offset,
      ],
      [
        midLat - perpLat * offset,
        midLng - perpLng * offset,
      ],
      [
        midLat + perpLat * offset * 1.5,
        midLng + perpLng * offset * 1.5,
      ],
      [
        midLat - perpLat * offset * 1.5,
        midLng - perpLng * offset * 1.5,
      ],
    ];
  }

  // ------------------------------------------------------------
  // REMOVE DUPLICATE ROUTES
  // ------------------------------------------------------------

  static bool _isDifferentRoute(
    RouteOption newRoute,
    List<RouteOption> existingRoutes,
  ) {
    for (final existing in existingRoutes) {
      final distanceDifference =
          (newRoute.distanceMeters -
                  existing.distanceMeters)
              .abs();

      final percentageDifference =
          distanceDifference /
              max(
                existing.distanceMeters,
                1,
              );

      // If the distances are extremely close,
      // treat them as probably the same route.
      if (percentageDifference < 0.03) {
        continue;
      }

      // Distance differs enough.
      return true;
    }

    return existingRoutes.isEmpty;
  }
}