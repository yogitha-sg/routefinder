import '../models/road_segment.dart';

class RiskService {
  static RiskLevel calculateRisk({
    required double rainfall,
    required double elevation,
    required double drainageDistance,
  }) {
    // Prototype risk model.
    //
    // Higher rainfall      → higher risk
    // Lower elevation      → higher risk
    // Longer drainage path → higher risk

    final rainfallFactor = rainfall / 120.0;

    final elevationFactor =
        (5.0 / elevation).clamp(0.0, 3.0);

    final drainageFactor =
        (drainageDistance / 200.0).clamp(0.0, 3.0);

    final risk =
        rainfallFactor *
        elevationFactor *
        drainageFactor *
        0.25;

    if (risk < 0.4) {
      return RiskLevel.safe;
    } else if (risk < 0.7) {
      return RiskLevel.moderate;
    } else {
      return RiskLevel.impassable;
    }
  }
}