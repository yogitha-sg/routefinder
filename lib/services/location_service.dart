import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<Position> getCurrentLocation() async {
    // Check whether location service is enabled.
    bool serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    // Check current permission.
    LocationPermission permission =
        await Geolocator.checkPermission();

    // Ask user for permission if needed.
    if (permission == LocationPermission.denied) {
      permission =
          await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }

    // Permission permanently denied.
    if (permission ==
        LocationPermission.deniedForever) {
      throw Exception(
        'Location permission permanently denied.',
      );
    }

    // Get current GPS position.
    return await Geolocator.getCurrentPosition(
      locationSettings:
          const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }
}