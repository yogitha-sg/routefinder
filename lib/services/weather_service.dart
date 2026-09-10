import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  static const String _baseUrl =
      'https://api.open-meteo.com/v1/forecast';

  /// ----------------------------------------------------------
  /// GET CURRENT RAINFALL
  /// ----------------------------------------------------------

  static Future<double> getCurrentRainfall({
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse(
      '$_baseUrl'
      '?latitude=$latitude'
      '&longitude=$longitude'
      '&current=rain,precipitation'
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
        'Weather API error: ${response.statusCode}',
      );
    }

    final data =
        jsonDecode(response.body) as Map<String, dynamic>;

    final current =
        data['current'] as Map<String, dynamic>?;

    if (current == null) {
      throw Exception('Current weather data unavailable');
    }

    final rain = current['rain'];

    if (rain == null) {
      return 0.0;
    }

    return (rain as num).toDouble();
  }

  /// ----------------------------------------------------------
  /// GET RAINFALL FOR MULTIPLE POINTS
  /// ----------------------------------------------------------

  static Future<List<double>> getRainfallForPoints(
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
        final rainfall =
            await getCurrentRainfall(
          latitude: point[0],
          longitude: point[1],
        );

        results.add(rainfall);
      } catch (_) {
        // Keep the route calculation alive
        // if one weather request fails.
        results.add(0.0);
      }
    }

    return results;
  }

  /// ----------------------------------------------------------
  /// GET AVERAGE RAINFALL ALONG ROUTE
  /// ----------------------------------------------------------

  static Future<double> getRouteRainfall(
    List<List<double>> routeCoordinates,
  ) async {
    if (routeCoordinates.isEmpty) {
      return 0.0;
    }

    final samplePoints =
        _getSamplePoints(routeCoordinates);

    final rainfallValues =
        await getRainfallForPoints(
      samplePoints,
    );

    if (rainfallValues.isEmpty) {
      return 0.0;
    }

    final total =
        rainfallValues.reduce(
      (a, b) => a + b,
    );

    return total / rainfallValues.length;
  }

  /// ----------------------------------------------------------
  /// GET MAXIMUM RAINFALL ALONG ROUTE
  /// ----------------------------------------------------------

  static Future<double> getMaximumRouteRainfall(
    List<List<double>> routeCoordinates,
  ) async {
    if (routeCoordinates.isEmpty) {
      return 0.0;
    }

    final samplePoints =
        _getSamplePoints(routeCoordinates);

    final rainfallValues =
        await getRainfallForPoints(
      samplePoints,
    );

    if (rainfallValues.isEmpty) {
      return 0.0;
    }

    return rainfallValues.reduce(
      (a, b) => a > b ? a : b,
    );
  }

  /// ----------------------------------------------------------
  /// SELECT SAMPLE POINTS
  /// ----------------------------------------------------------

  static List<List<double>> _getSamplePoints(
    List<List<double>> routeCoordinates,
  ) {
    const maxSamples = 5;

    if (routeCoordinates.length <= maxSamples) {
      return List<List<double>>.from(
        routeCoordinates,
      );
    }

    final samplePoints =
        <List<double>>[];

    for (int i = 0; i < maxSamples; i++) {
      final index =
          ((routeCoordinates.length - 1) *
                  i /
                  (maxSamples - 1))
              .round();

      samplePoints.add(
        routeCoordinates[index],
      );
    }

    return samplePoints;
  }
}