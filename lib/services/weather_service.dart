
import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  /// Gets current rainfall at one location.
  static Future<double> getCurrentRainfall({
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$latitude'
      '&longitude=$longitude'
      '&current=rain,precipitation'
      '&timezone=auto',
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch weather data');
    }

    final data = jsonDecode(response.body);

    final rain = data['current']['rain'];

    return (rain as num).toDouble();
  }

  /// Gets rainfall for multiple locations.
  ///
  /// Returns one rainfall value for each latitude/longitude pair.
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

      final latitude = point[0];
      final longitude = point[1];

      try {
        final rainfall = await getCurrentRainfall(
          latitude: latitude,
          longitude: longitude,
        );

        results.add(rainfall);
      } catch (e) {
        // If one point fails, continue checking the remaining points.
        results.add(0);
      }
    }

    return results;
  }

  /// Calculates the average rainfall across a route.
  static Future<double> getRouteRainfall(
    List<List<double>> routeCoordinates,
  ) async {
    if (routeCoordinates.isEmpty) {
      return 0;
    }

    // We don't need to request weather for every road coordinate.
    // Pick up to 5 evenly distributed points along the route.
    final samplePoints = <List<double>>[];

    const maxSamples = 5;

    if (routeCoordinates.length <= maxSamples) {
      samplePoints.addAll(routeCoordinates);
    } else {
      for (int i = 0; i < maxSamples; i++) {
        final index = ((routeCoordinates.length - 1) * i /
                (maxSamples - 1))
            .round();

        samplePoints.add(routeCoordinates[index]);
      }
    }

    final rainfallValues = await getRainfallForPoints(samplePoints);

    if (rainfallValues.isEmpty) {
      return 0;
    }

    final total = rainfallValues.reduce((a, b) => a + b);

    return total / rainfallValues.length;
  }

  /// Gets the maximum rainfall detected along the sampled route points.
  static Future<double> getMaximumRouteRainfall(
    List<List<double>> routeCoordinates,
  ) async {
    if (routeCoordinates.isEmpty) {
      return 0;
    }

    const maxSamples = 5;

    final samplePoints = <List<double>>[];

    if (routeCoordinates.length <= maxSamples) {
      samplePoints.addAll(routeCoordinates);
    } else {
      for (int i = 0; i < maxSamples; i++) {
        final index = ((routeCoordinates.length - 1) * i /
                (maxSamples - 1))
            .round();

        samplePoints.add(routeCoordinates[index]);
      }
    }

    final rainfallValues = await getRainfallForPoints(samplePoints);

    if (rainfallValues.isEmpty) {
      return 0;
    }

    return rainfallValues.reduce((a, b) => a > b ? a : b);
  }
}
