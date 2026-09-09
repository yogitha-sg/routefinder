import 'dart:convert';
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
  static const String _baseUrl = 'https://router.project-osrm.org';

  static Future<List<RouteOption>> getRoutes({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    final url = Uri.parse(
      '$_baseUrl/route/v1/driving/'
      '$startLng,$startLat;'
      '$endLng,$endLat'
      '?alternatives=true'
      '&steps=true'
      '&overview=full'
      '&geometries=geojson',
    );

    final response = await http.get(url);

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

      final coordinates = rawCoordinates.map<List<double>>((point) {
        return [
          (point[1] as num).toDouble(), // latitude
          (point[0] as num).toDouble(), // longitude
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
}