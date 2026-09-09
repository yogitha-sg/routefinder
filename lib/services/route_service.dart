import '../models/road_segment.dart';

class RouteService {
  /// Returns the safest available road.
  ///
  /// Priority:
  /// 1. Safe roads
  /// 2. Moderate roads
  /// 3. Impassable roads are avoided
  static RoadSegment? findSafestRoad(
    List<RoadSegment> roads,
  ) {
    // Remove impassable roads.
    final availableRoads = roads
        .where(
          (road) => road.riskLevel != RiskLevel.impassable,
        )
        .toList();

    // If every road is impassable, no safe route exists.
    if (availableRoads.isEmpty) {
      return null;
    }

    // Safe roads are preferred over moderate roads.
    availableRoads.sort(
      (a, b) {
        return riskPriority(a.riskLevel)
            .compareTo(riskPriority(b.riskLevel));
      },
    );

    return availableRoads.first;
  }

  /// Gives each risk level a priority.
  static int riskPriority(RiskLevel level) {
    switch (level) {
      case RiskLevel.safe:
        return 0;

      case RiskLevel.moderate:
        return 1;

      case RiskLevel.impassable:
        return 2;
    }
  }

  /// Returns all roads sorted from safest to most dangerous.
  static List<RoadSegment> rankRoads(
    List<RoadSegment> roads,
  ) {
    final sortedRoads = List<RoadSegment>.from(roads);

    sortedRoads.sort(
      (a, b) {
        return riskPriority(a.riskLevel)
            .compareTo(riskPriority(b.riskLevel));
      },
    );

    return sortedRoads;
  }
}