import 'dart:convert';
import 'package:http/http.dart' as http;

class FloodService {
  static const String _baseUrl =
      'https://flood-api.open-meteo.com/v1/flood';

  /// Gets the latest available river discharge for a location.
  ///
  /// Returns river discharge in m³/s.
  static Future<double> getRiverDischarge({
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse(
      '$_baseUrl'
      '?latitude=$latitude'
      '&longitude=$longitude'
      '&daily=river_discharge'
      '&forecast_days=1'
      '&timezone=auto',
    );

    final response = await http.get(
      url,
      headers: {
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Flood API error: ${response.statusCode}',
      );
    }

    final data =
        jsonDecode(response.body) as Map<String, dynamic>;

    final daily =
        data['daily'] as Map<String, dynamic>?;

    if (daily == null) {
      throw Exception(
        'Flood data unavailable',
      );
    }

    final values =
        daily['river_discharge'];

    if (values == null ||
        values is! List ||
        values.isEmpty) {
      return 0.0;
    }

    final firstValue = values.first;

    if (firstValue == null) {
      return 0.0;
    }

    return (firstValue as num).toDouble();
  }

  /// Gets flood information for several points.
  static Future<List<double>> getDischargeForPoints(
    List<List<double>> points,
  ) async {
    if (points.isEmpty) {
      return [];
    }

    final results = <double>[];

    for (final point in points) {
      if (point.length < 2) {
        continue;
      }

      try {
        final discharge =
            await getRiverDischarge(
          latitude: point[0],
          longitude: point[1],
        );

        results.add(discharge);
      } catch (e) {
        results.add(0.0);
      }
    }

    return results;
  }

  /// Samples a route and returns its maximum
  /// river discharge indicator.
  static Future<double> getMaximumRouteDischarge(
    List<List<double>> routeCoordinates,
  ) async {
    if (routeCoordinates.isEmpty) {
      return 0.0;
    }

    final samplePoints =
        _getSamplePoints(routeCoordinates);

    final values =
        await getDischargeForPoints(
      samplePoints,
    );

    if (values.isEmpty) {
      return 0.0;
    }

    return values.reduce(
      (a, b) => a > b ? a : b,
    );
  }

  static List<List<double>> _getSamplePoints(
    List<List<double>> coordinates,
  ) {
    const maxSamples = 5;

    if (coordinates.length <= maxSamples) {
      return List<List<double>>.from(
        coordinates,
      );
    }

    final samples = <List<double>>[];

    for (int i = 0; i < maxSamples; i++) {
      final index =
          ((coordinates.length - 1) *
                  i /
                  (maxSamples - 1))
              .round();

      samples.add(
        coordinates[index],
      );
    }

    return samples;
  }
}