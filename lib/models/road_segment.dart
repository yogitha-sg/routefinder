import 'package:latlong2/latlong.dart';

enum RiskLevel {
  safe,
  moderate,
  impassable,
}

class RoadSegment {
  final String name;
  final double elevation;
  final double drainageDistance;
  final List<LatLng> points;

  RiskLevel riskLevel;

  RoadSegment({
    required this.name,
    required this.elevation,
    required this.drainageDistance,
    required this.points,
    this.riskLevel = RiskLevel.safe,
  });
}