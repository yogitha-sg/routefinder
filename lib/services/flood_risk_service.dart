
import 'package:latlong2/latlong.dart';

class FloodRiskResult {
  final double score;
  final int exposedPoints;

  FloodRiskResult({
    required this.score,
    required this.exposedPoints,
  });
}

class FloodRiskService {
  /// Calculates flood exposure for a route.
  ///
  /// The current version uses known/sample flood-prone zones.
  /// These zones can later be replaced with real flood/waterlogging
  /// datasets or live reports.
  static FloodRiskResult calculateFloodExposure(
    List<List<double>> routeCoordinates,
  ) {
    if (routeCoordinates.isEmpty) {
      return FloodRiskResult(
        score: 0,
        exposedPoints: 0,
      );
    }

    int exposedPoints = 0;

    for (final coordinate in routeCoordinates) {
      if (coordinate.length < 2) continue;

      final latitude = coordinate[0];
      final longitude = coordinate[1];

      final point = LatLng(latitude, longitude);

      if (_isFloodProne(point)) {
        exposedPoints++;
      }
    }

    final exposurePercentage =
        (exposedPoints / routeCoordinates.length) * 100;

    double score;

    if (exposurePercentage >= 50) {
      score = 40;
    } else if (exposurePercentage >= 30) {
      score = 30;
    } else if (exposurePercentage >= 15) {
      score = 20;
    } else if (exposurePercentage > 0) {
      score = 10;
    } else {
      score = 0;
    }

    return FloodRiskResult(
      score: score,
      exposedPoints: exposedPoints,
    );
  }

  /// Checks whether a coordinate falls inside a flood-prone zone.
  ///
  /// IMPORTANT:
  /// These are only placeholder zones for the prototype.
  /// They should NOT be presented as official flood predictions.
  static bool _isFloodProne(LatLng point) {
    // Example zone 1
    if (_insideArea(
      point,
      minLat: 12.90,
      maxLat: 12.96,
      minLng: 80.20,
      maxLng: 80.27,
    )) {
      return true;
    }

    // Example zone 2
    if (_insideArea(
      point,
      minLat: 13.00,
      maxLat: 13.06,
      minLng: 80.18,
      maxLng: 80.25,
    )) {
      return true;
    }

    return false;
  }

  static bool _insideArea(
    LatLng point, {
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
  }) {
    return point.latitude >= minLat &&
        point.latitude <= maxLat &&
        point.longitude >= minLng &&
        point.longitude <= maxLng;
  }
}
