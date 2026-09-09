import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
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
}