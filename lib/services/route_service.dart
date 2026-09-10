
import 'dart:convert';

import 'package:http/http.dart' as http;

class RouteStep {
  final String instruction;
  final String formattedDistance;

  RouteStep({
    required this.instruction,
    required this.formattedDistance,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    final distance = (json['distance'] ?? 0).toDouble();

    return RouteStep(
      instruction: _getInstruction(json),
      formattedDistance: _formatDistance(distance),
    );
  }

  static String _getInstruction(Map<String, dynamic> json) {
    // OSRM normally provides a "maneuver" object.
    final maneuver = json['maneuver'];

    if (maneuver is Map<String, dynamic>) {
      final type = maneuver['type']?.toString() ?? '';
      final modifier = maneuver['modifier']?.toString() ?? '';

      if (type == 'depart') {
        return 'Start your journey';
      }

      if (type == 'arrive') {
        return 'You have arrived at your destination';
      }

      if (type == 'turn') {
        if (modifier.isNotEmpty) {
          return 'Turn $modifier';
        }

        return 'Turn';
      }

      if (type == 'new name') {
        return 'Continue';
      }

      if (type == 'roundabout') {
        return 'Enter the roundabout';
      }

      if (type == 'merge') {
        return 'Merge';
      }

      if (type == 'fork') {
        if (modifier.isNotEmpty) {
          return 'Keep $modifier at the fork';
        }

        return 'Keep at the fork';
      }

      if (type == 'continue') {
        return 'Continue straight';
      }

      if (type == 'on ramp') {
        return 'Take the ramp';
      }

      if (type == 'off ramp') {
        return 'Take the exit ramp';
      }

      if (type == 'exit roundabout') {
        return 'Exit the roundabout';
      }

      if (type == 'notification') {
        return 'Continue';
      }
    }

    return 'Continue on this road';
  }

  static String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }

    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}

class RouteOption {
  final List<List<double>> coordinates;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteStep> steps;

  RouteOption({
    required this.coordinates,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
  });

  double get distanceKm => distanceMeters / 1000;

  factory RouteOption.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'];

    final List<List<double>> coordinates = [];

    if (geometry is Map<String, dynamic>) {
      final geometryCoordinates = geometry['coordinates'];

      if (geometryCoordinates is List) {
        for (final point in geometryCoordinates) {
          if (point is List && point.length >= 2) {
            final longitude = (point[0] as num).toDouble();
            final latitude = (point[1] as num).toDouble();

            coordinates.add([
              latitude,
              longitude,
            ]);
          }
        }
      }
    }

    final List<RouteStep> steps = [];

    final legs = json['legs'];

    if (legs is List) {
      for (final leg in legs) {
        if (leg is Map<String, dynamic>) {
          final legSteps = leg['steps'];

          if (legSteps is List) {
            for (final step in legSteps) {
              if (step is Map<String, dynamic>) {
                steps.add(
                  RouteStep.fromJson(step),
                );
              }
            }
          }
        }
      }
    }

    return RouteOption(
      coordinates: coordinates,
      distanceMeters: (json['distance'] ?? 0).toDouble(),
      durationSeconds: (json['duration'] ?? 0).toDouble(),
      steps: steps,
    );
  }
}

class RouteService {
  static const String _baseUrl = 'https://router.project-osrm.org/route/v1/driving';

  static Future<List<RouteOption>> getRoutes({
    required double startLatitude,
    required double startLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) async {
    final url = Uri.parse(
      '$_baseUrl/'
      '$startLongitude,$startLatitude;'
      '$destinationLongitude,$destinationLatitude'
      '?overview=full'
      '&geometries=geojson'
      '&steps=true'
      '&alternatives=true',
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to get routes. Status code: ${response.statusCode}',
      );
    }

    final Map<String, dynamic> data =
        jsonDecode(response.body) as Map<String, dynamic>;

    if (data['code'] != 'Ok') {
      throw Exception(
        'Routing service error: ${data['message'] ?? data['code']}',
      );
    }

    final routes = data['routes'];

    if (routes is! List || routes.isEmpty) {
      throw Exception('No routes found.');
    }

    return routes
        .whereType<Map<String, dynamic>>()
        .map(
          (route) => RouteOption.fromJson(route),
        )
        .toList();
  }
}
