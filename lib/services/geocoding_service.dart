import 'dart:convert';
import 'package:http/http.dart' as http;

class GeocodingService {
  static Future<String> getPlaceName({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse'
      '?format=jsonv2'
      '&lat=$latitude'
      '&lon=$longitude'
      '&zoom=18'
      '&addressdetails=1',
      );

    try {
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'HydroPulse Flutter App',
          'Accept-Language': 'en',
        },
      );

      if (response.statusCode != 200) {
        return _fallback(latitude, longitude);
      }

      final data = jsonDecode(response.body);

      final address = data['address'];

      if (address == null) {
        return data['display_name'] ??
            _fallback(latitude, longitude);
      }

      // Try to get the most useful place name first.
      final road = address['road'];
      final neighbourhood = address['neighbourhood'];
      final suburb = address['suburb'];
      final city = address['city'] ??
          address['town'] ??
          address['village'];

      if (road != null && road.toString().isNotEmpty) {
        String result = road.toString();

        if (suburb != null &&
            suburb.toString().isNotEmpty) {
          result += ', ${suburb.toString()}';
        } else if (neighbourhood != null &&
            neighbourhood.toString().isNotEmpty) {
          result += ', ${neighbourhood.toString()}';
        }

        if (city != null &&
            city.toString().isNotEmpty) {
          result += ', ${city.toString()}';
        }

        return result;
      }

      if (suburb != null &&
          suburb.toString().isNotEmpty) {
        if (city != null &&
            city.toString().isNotEmpty) {
          return '${suburb.toString()}, ${city.toString()}';
        }

        return suburb.toString();
      }

      if (city != null &&
          city.toString().isNotEmpty) {
        return city.toString();
      }

      return data['display_name'] ??
          _fallback(latitude, longitude);
    } catch (e) {
      return _fallback(latitude, longitude);
    }
  }

  static String _fallback(
    double latitude,
    double longitude,
  ) {
    return '${latitude.toStringAsFixed(5)}, '
        '${longitude.toStringAsFixed(5)}';
  }
}