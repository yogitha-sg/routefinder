import 'elevation_service.dart';

Future<void> testElevation() async {
  final elevations =
      await ElevationService.getElevations([
    [13.0827, 80.2707],
    [13.0600, 80.2500],
    [13.0400, 80.2200],
  ]);

  print('REAL ELEVATION TEST');
  print(elevations);
}