import 'dart:convert';
import 'package:http/http.dart' as http;

class ElevationService {
  static const String _baseUrl =
      'https://api.open-meteo.com/v1/elevation';

  /// Gets elevation values for multiple latitude/longitude points.
  ///
  /// Returns elevations in meters above mean sea level.
  static Future<List<double>> getElevations(
    List<List<double>> coordinates,
  ) async {
    if (coordinates.isEmpty) {
      return [];
    }

    // Open-Meteo accepts up to 100 coordinates per request.
    final selectedPoints = coordinates.length > 100
        ? _sampleCoordinates(coordinates, 100)
        : coordinates;

    final latitudes = selectedPoints
        .map((point) => point[0].toStringAsFixed(6))
        .join(',');

    final longitudes = selectedPoints
        .map((point) => point[1].toStringAsFixed(6))
        .join(',');

    final uri = Uri.parse(
      '$_baseUrl'
      '?latitude=$latitudes'
      '&longitude=$longitudes',
    );

    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Elevation service failed: ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body);

    if (data['elevation'] == null) {
      throw Exception(
        'Elevation data unavailable',
      );
    }

    return (data['elevation'] as List)
        .map(
          (value) => (value as num).toDouble(),
        )
        .toList();
  }

  /// Samples a route evenly when it contains more than 100 points.
  static List<List<double>> _sampleCoordinates(
    List<List<double>> coordinates,
    int maxPoints,
  ) {
    if (coordinates.length <= maxPoints) {
      return coordinates;
    }

    final result = <List<double>>[];

    final step =
        (coordinates.length - 1) / (maxPoints - 1);

    for (int i = 0; i < maxPoints; i++) {
      final index =
          (i * step).round();

      result.add(
        coordinates[
            index.clamp(0, coordinates.length - 1)],
      );
    }

    return result;
  }
}