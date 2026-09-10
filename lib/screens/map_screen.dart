import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../services/flood_service.dart';
import '../services/weather_service.dart';
import '../services/route_service.dart';
import '../services/location_service.dart';
import '../services/elevation_service.dart';
import '../services/voice_service.dart';
import '../models/road_segment.dart';

class MapScreen extends StatefulWidget {
  final String travelMode;
  final bool selectionMode;

  const MapScreen({
    super.key,
    this.travelMode = 'Car',
    this.selectionMode = true,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const primaryColor = Color(0xFF2563EB);
  static const darkColor = Color(0xFF1E3A8A);

  final MapController mapController = MapController();

  Position? currentPosition;
  LatLng? destination;

  String? destinationAddress;

  bool loadingAddress = false;
  bool loadingLocation = false;
  bool loadingRoutes = false;
  bool searchingHospitals = false;

  // ==========================================================
  // VOICE
  // ==========================================================

  bool voiceEnabled = true;

  // Prevent multiple automatic announcements at once.
  bool speaking = false;

  String? errorMessage;

  List<RouteOption> routes = [];
  int selectedRouteIndex = 0;

  double rainfall = 0.0;
  double elevation = 0.0;
  double drainageDistance = 0.0;

  RiskLevel selectedRisk = RiskLevel.safe;

  // ==========================================================
  // EMERGENCY / HOSPITAL
  // ==========================================================

  String? selectedHospitalName;
  String? selectedHospitalAddress;

  double? selectedHospitalDistance;
  double? selectedHospitalScore;

  bool get isAmbulance =>
      widget.travelMode.toLowerCase() == 'ambulance';

  bool get isRescue =>
      widget.travelMode.toLowerCase() == 'rescue';

  bool get isEmergency =>
      isAmbulance || isRescue;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  // ==========================================================
  // VOICE FUNCTIONS
  // ==========================================================

  Future<void> _speak(String message) async {
    if (!voiceEnabled || message.trim().isEmpty) {
      return;
    }

    if (speaking) {
      await VoiceService.instance.stop();
    }

    speaking = true;

    try {
      await VoiceService.instance.speak(message);
    } catch (e) {
      debugPrint('Voice error: $e');
    } finally {
      speaking = false;
    }
  }

  Future<void> _speakRouteSummary(
    RouteOption route,
  ) async {
    if (!voiceEnabled) return;

    final distance =
        _formatDistance(route.distanceMeters);

    final duration =
        _formatDuration(route.durationSeconds);

    final risk =
        _riskVoiceText(selectedRisk);

    String message;

    if (isAmbulance) {
      final hospital =
          selectedHospitalName ?? 'the selected hospital';

      message =
          'Emergency route selected to $hospital. '
          'Distance $distance. '
          'Estimated travel time $duration. '
          'Current route risk is $risk.';
    } else if (isRescue) {
      message =
          'Safest rescue route selected. '
          'Distance $distance. '
          'Estimated travel time $duration. '
          'Current route risk is $risk.';
    } else {
      message =
          'Safest ${widget.travelMode} route selected. '
          'Distance $distance. '
          'Estimated travel time $duration. '
          'Current route risk is $risk.';
    }

    await _speak(message);
  }

  Future<void> _speakDirections(
    RouteOption route,
  ) async {
    if (!voiceEnabled) return;

    if (route.steps.isEmpty) {
      await _speakRouteSummary(route);
      return;
    }

    final buffer = StringBuffer();

    if (isAmbulance &&
        selectedHospitalName != null) {
      buffer.write(
        'Proceed to $selectedHospitalName. ',
      );
    } else if (isRescue) {
      buffer.write(
        'Rescue route directions. ',
      );
    } else {
      buffer.write(
        '${widget.travelMode} route directions. ',
      );
    }

    buffer.write(
      'Total distance '
      '${_formatDistance(route.distanceMeters)}. ',
    );

    buffer.write(
      'Estimated time '
      '${_formatDuration(route.durationSeconds)}. ',
    );

    buffer.write(
      'Route risk is '
      '${_riskVoiceText(selectedRisk)}. ',
    );

    // Read up to the first 5 steps.
    final stepCount =
        math.min(route.steps.length, 5);

    for (int i = 0; i < stepCount; i++) {
      final step = route.steps[i];

      buffer.write(
        'Step ${i + 1}. '
        '${step.instruction}. '
        '${step.formattedDistance}. ',
      );
    }

    await _speak(buffer.toString());
  }

  String _riskVoiceText(
    RiskLevel risk,
  ) {
    switch (risk) {
      case RiskLevel.safe:
        return 'safe';

      case RiskLevel.moderate:
        return 'moderate';

      case RiskLevel.impassable:
        return 'high';
    }
  }

  Future<void> _toggleVoice() async {
    final newValue = !voiceEnabled;

    setState(() {
      voiceEnabled = newValue;
    });

    await VoiceService.instance
        .setEnabled(newValue);

    if (!newValue) {
      _showMessage('Voice navigation muted.');
      return;
    }

    _showMessage('Voice navigation enabled.');

    if (routes.isNotEmpty &&
        selectedRouteIndex < routes.length) {
      await _speakRouteSummary(
        routes[selectedRouteIndex],
      );
    }
  }

  // ==========================================================
  // LOCATION
  // ==========================================================

  Future<void> _initializeLocation() async {
    await _getCurrentLocation();

    if (!mounted) return;

    if (isAmbulance &&
        currentPosition != null) {
      await _findBestHospitalRoute();
    }
  }

  Future<void> _getCurrentLocation() async {
    if (mounted) {
      setState(() {
        loadingLocation = true;
        errorMessage = null;
      });
    }

    try {
      final position =
          await LocationService.getCurrentLocation();

      if (!mounted) return;

      setState(() {
        currentPosition = position;
        loadingLocation = false;
      });

      mapController.move(
        LatLng(
          position.latitude,
          position.longitude,
        ),
        15,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loadingLocation = false;
        errorMessage = e.toString();
      });

      _showMessage(
        'Unable to get your current location.',
      );
    }
  }

  // ==========================================================
  // MAP TAP
  // ==========================================================

  Future<void> _onMapTap(
    TapPosition tapPosition,
    LatLng point,
  ) async {
    if (isAmbulance) {
      _showMessage(
        'Ambulance mode automatically selects the best hospital.',
      );
      return;
    }

    setState(() {
      destination = point;

      destinationAddress =
          'Getting location name...';

      loadingAddress = true;

      routes = [];
      selectedRouteIndex = 0;

      errorMessage = null;
    });

    await _getDestinationAddress(point);
  }

  // ==========================================================
  // REVERSE GEOCODING
  // ==========================================================

  Future<void> _getDestinationAddress(
    LatLng point,
  ) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json'
        '&lat=${point.latitude}'
        '&lon=${point.longitude}'
        '&zoom=18'
        '&addressdetails=1',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent':
              'HydroPulse Flutter App',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data =
            jsonDecode(response.body)
                as Map<String, dynamic>;

        final displayName =
            data['display_name'] as String?;

        setState(() {
          destinationAddress =
              displayName ??
                  'Selected destination';

          loadingAddress = false;
        });
      } else {
        setState(() {
          destinationAddress =
              'Selected destination';

          loadingAddress = false;
        });
      }
    } catch (e) {
      debugPrint(
        'Reverse geocoding error: $e',
      );

      if (!mounted) return;

      setState(() {
        destinationAddress =
            'Selected destination';

        loadingAddress = false;
      });
    }
  }

  // ==========================================================
  // FIND SAFEST ROUTE
  // ==========================================================

  Future<void> _findSafestRoute() async {
    if (isAmbulance) {
      await _findBestHospitalRoute();
      return;
    }

    if (currentPosition == null) {
      _showMessage(
        'Please get your current location first.',
      );
      return;
    }

    if (destination == null) {
      _showMessage(
        'Tap on the map to select a destination.',
      );
      return;
    }

    setState(() {
      loadingRoutes = true;
      errorMessage = null;
      routes = [];
    });

    try {
      final routeResults =
          await RouteService.getRoutes(
        startLatitude:
            currentPosition!.latitude,
        startLongitude:
            currentPosition!.longitude,
        destinationLatitude:
            destination!.latitude,
        destinationLongitude:
            destination!.longitude,
      );

      if (!mounted) return;

      if (routeResults.isEmpty) {
        setState(() {
          loadingRoutes = false;
          errorMessage = 'No routes found.';
        });

        _showMessage(
          'No routes found for this destination.',
        );

        return;
      }

      int safestRouteIndex = 0;
      double bestScore = double.infinity;

      for (
        int i = 0;
        i < routeResults.length;
        i++
      ) {
        final route =
            routeResults[i];

        final riskData =
            await _calculateRouteRisk(route);

        final riskScore =
            riskData['score'] as double;

        final routeRainfall =
            riskData['rainfall'] as double;

        final routeElevation =
            riskData['elevation'] as double;

        debugPrint(
          '--------------------------------',
        );

        debugPrint(
          'Route ${i + 1}',
        );

        debugPrint(
          'Rainfall: '
          '${routeRainfall.toStringAsFixed(2)} mm',
        );

        debugPrint(
          'Elevation: '
          '${routeElevation.toStringAsFixed(2)} m',
        );

        debugPrint(
          'Risk Score: '
          '${riskScore.toStringAsFixed(2)}',
        );

        debugPrint(
          'Travel time: '
          '${_formatDuration(route.durationSeconds)}',
        );

        debugPrint(
          '--------------------------------',
        );

        final routeScore =
            riskScore * 1000 +
            route.durationSeconds / 60;

        if (routeScore < bestScore) {
          bestScore = routeScore;
          safestRouteIndex = i;
        }
      }

      final safestRoute =
          routeResults[safestRouteIndex];

      await _loadRiskInformation(
        safestRoute,
      );

      if (!mounted) return;

      setState(() {
        routes = routeResults;

        selectedRouteIndex =
            safestRouteIndex;

        loadingRoutes = false;
      });

      fitMapToRoute(
        safestRoute,
      );

      _showMessage(
        'Safest route selected: '
        'Route ${safestRouteIndex + 1}',
      );

      // VOICE
      await _speakRouteSummary(
        safestRoute,
      );
    } catch (e) {
      debugPrint(
        'Route error: $e',
      );

      if (!mounted) return;

      setState(() {
        loadingRoutes = false;
        errorMessage = e.toString();
      });

      _showMessage(
        'Unable to find routes. '
        'Check your internet connection.',
      );
    }
  }

  // ==========================================================
  // FIND NEARBY HOSPITALS
  // ==========================================================

  Future<List<Map<String, dynamic>>>
      _findNearbyHospitals() async {
    if (currentPosition == null) {
      return [];
    }

    final lat =
        currentPosition!.latitude;

    final lon =
        currentPosition!.longitude;

    final query = '''
[out:json][timeout:20];
(
  node["amenity"="hospital"](around:10000,$lat,$lon);
  way["amenity"="hospital"](around:10000,$lat,$lon);
  relation["amenity"="hospital"](around:10000,$lat,$lon);
);
out center tags;
''';

    try {
      final url = Uri.parse(
        'https://overpass-api.de/api/interpreter',
      );

      final response = await http.post(
        url,
        body: {
          'data': query,
        },
        headers: {
          'User-Agent':
              'HydroPulse Flutter App',
        },
      );

      if (response.statusCode != 200) {
        debugPrint(
          'Hospital search failed: '
          '${response.statusCode}',
        );

        return [];
      }

      final data =
          jsonDecode(response.body)
              as Map<String, dynamic>;

      final elements =
          data['elements']
              as List<dynamic>?;

      if (elements == null) {
        return [];
      }

      final hospitals =
          <Map<String, dynamic>>[];

      for (final element
          in elements) {
        final item =
            element
                as Map<String, dynamic>;

        final tags =
            item['tags']
                as Map<String, dynamic>?;

        if (tags == null) continue;

        double? hospitalLat;
        double? hospitalLon;

        if (item['lat'] != null &&
            item['lon'] != null) {
          hospitalLat =
              (item['lat'] as num)
                  .toDouble();

          hospitalLon =
              (item['lon'] as num)
                  .toDouble();
        } else {
          final center =
              item['center']
                  as Map<String, dynamic>?;

          if (center != null &&
              center['lat'] != null &&
              center['lon'] != null) {
            hospitalLat =
                (center['lat'] as num)
                    .toDouble();

            hospitalLon =
                (center['lon'] as num)
                    .toDouble();
          }
        }

        if (hospitalLat == null ||
            hospitalLon == null) {
          continue;
        }

        final name =
            tags['name']?.toString() ??
                'Hospital';

        final distance =
            Geolocator.distanceBetween(
          lat,
          lon,
          hospitalLat,
          hospitalLon,
        );

        hospitals.add({
          'name': name,
          'latitude': hospitalLat,
          'longitude': hospitalLon,
          'distance': distance,
          'address':
              tags['addr:street']
                      ?.toString() ??
                  '',
        });
      }

      final uniqueHospitals =
          <String, Map<String, dynamic>>{};

      for (final hospital
          in hospitals) {
        final key =
            '${hospital['name']}_'
            '${(hospital['latitude'] as double).toStringAsFixed(4)}_'
            '${(hospital['longitude'] as double).toStringAsFixed(4)}';

        uniqueHospitals[key] =
            hospital;
      }

      final result =
          uniqueHospitals.values.toList();

      result.sort(
        (a, b) =>
            (a['distance'] as double)
                .compareTo(
              b['distance'] as double,
            ),
      );

      if (result.length > 5) {
        return result.take(5).toList();
      }

      return result;
    } catch (e) {
      debugPrint(
        'Hospital search error: $e',
      );

      return [];
    }
  }

  // ==========================================================
  // AMBULANCE ROUTING
  // ==========================================================

  Future<void> _findBestHospitalRoute() async {
    if (currentPosition == null) {
      _showMessage(
        'Current location is required for ambulance routing.',
      );
      return;
    }

    if (mounted) {
      setState(() {
        searchingHospitals = true;
        loadingRoutes = true;
        routes = [];
        selectedHospitalName = null;
        selectedHospitalAddress = null;
        selectedHospitalDistance = null;
        selectedHospitalScore = null;
        errorMessage = null;
      });
    }

    try {
      _showMessage(
        'Searching for nearby hospitals...',
      );

      final hospitals =
          await _findNearbyHospitals();

      if (!mounted) return;

      if (hospitals.isEmpty) {
        setState(() {
          searchingHospitals = false;
          loadingRoutes = false;
          errorMessage =
              'No nearby hospitals found.';
        });

        _showMessage(
          'No nearby hospitals were found.',
        );

        return;
      }

      double bestHospitalScore =
          double.infinity;

      Map<String, dynamic>? bestHospital;

      RouteOption? bestRoute;

      List<RouteOption>
          bestRouteAlternatives = [];

      for (final hospital
          in hospitals) {
        try {
          final hospitalLat =
              hospital['latitude']
                  as double;

          final hospitalLon =
              hospital['longitude']
                  as double;

          debugPrint(
            'Checking hospital: '
            '${hospital['name']}',
          );

          final hospitalRoutes =
              await RouteService.getRoutes(
            startLatitude:
                currentPosition!.latitude,
            startLongitude:
                currentPosition!.longitude,
            destinationLatitude:
                hospitalLat,
            destinationLongitude:
                hospitalLon,
          );

          if (hospitalRoutes.isEmpty) {
            continue;
          }

          double hospitalBestScore =
              double.infinity;

          RouteOption?
              hospitalBestRoute;

          for (final route
              in hospitalRoutes) {
            final riskData =
                await _calculateRouteRisk(
              route,
            );

            final riskScore =
                riskData['score']
                    as double;

            final emergencyScore =
                riskScore * 2000 +
                route.durationSeconds;

            if (emergencyScore <
                hospitalBestScore) {
              hospitalBestScore =
                  emergencyScore;

              hospitalBestRoute =
                  route;
            }
          }

          if (hospitalBestRoute == null) {
            continue;
          }

          final hospitalDistance =
              hospitalBestRoute
                  .distanceMeters;

          final hospitalTime =
              hospitalBestRoute
                  .durationSeconds;

          final combinedScore =
              hospitalBestScore +
              hospitalDistance * 0.05 +
              hospitalTime * 0.20;

          debugPrint(
            'Hospital: '
            '${hospital['name']}',
          );

          debugPrint(
            'Distance: '
            '${_formatDistance(hospitalDistance)}',
          );

          debugPrint(
            'ETA: '
            '${_formatDuration(hospitalTime)}',
          );

          debugPrint(
            'Hospital score: '
            '${combinedScore.toStringAsFixed(2)}',
          );

          if (combinedScore <
              bestHospitalScore) {
            bestHospitalScore =
                combinedScore;

            bestHospital =
                hospital;

            bestRoute =
                hospitalBestRoute;

            bestRouteAlternatives =
                hospitalRoutes;
          }
        } catch (e) {
          debugPrint(
            'Hospital route error: $e',
          );
        }
      }

      if (!mounted) return;

      if (bestHospital == null ||
          bestRoute == null) {
        setState(() {
          searchingHospitals = false;
          loadingRoutes = false;
          errorMessage =
              'No reachable hospital route found.';
        });

        _showMessage(
          'No safe hospital route could be found.',
        );

        return;
      }

      final hospitalLat =
          bestHospital['latitude']
              as double;

      final hospitalLon =
          bestHospital['longitude']
              as double;

      destination = LatLng(
        hospitalLat,
        hospitalLon,
      );

      selectedHospitalName =
          bestHospital['name'] as String;

      selectedHospitalAddress =
          bestHospital['address']
              as String?;

      selectedHospitalDistance =
          bestRoute.distanceMeters;

      selectedHospitalScore =
          bestHospitalScore;

      destinationAddress =
          selectedHospitalName;

      await _loadRiskInformation(
        bestRoute,
      );

      if (!mounted) return;

      setState(() {
        routes =
            bestRouteAlternatives;

        selectedRouteIndex =
            bestRouteAlternatives
                .indexOf(
          bestRoute!,
        );

        if (selectedRouteIndex < 0) {
          selectedRouteIndex = 0;
        }

        searchingHospitals = false;
        loadingRoutes = false;
      });

      fitMapToRoute(
        bestRoute,
      );

      _showMessage(
        'Best hospital route selected.',
      );

      // VOICE
      await _speakRouteSummary(
        bestRoute,
      );
    } catch (e) {
      debugPrint(
        'Ambulance routing error: $e',
      );

      if (!mounted) return;

      setState(() {
        searchingHospitals = false;
        loadingRoutes = false;
        errorMessage = e.toString();
      });

      _showMessage(
        'Unable to find a hospital route.',
      );
    }
  }

  // ==========================================================
  // CALCULATE RISK FOR ONE ROUTE
  // ==========================================================

  Future<Map<String, dynamic>>
      _calculateRouteRisk(
    RouteOption route,
  ) async {
    double routeRainfall = 0.0;
    double routeElevation = 0.0;

    try {
      routeRainfall =
          await WeatherService
              .getRouteRainfall(
        route.coordinates,
      );
    } catch (e) {
      debugPrint(
        'Rainfall error: $e',
      );
    }

    try {
      final elevations =
          await ElevationService
              .getElevations(
        route.coordinates,
      );

      if (elevations.isNotEmpty) {
        routeElevation =
            elevations.reduce(
                  (a, b) => a + b,
                ) /
                elevations.length;
      }
    } catch (e) {
      debugPrint(
        'Elevation error: $e',
      );
    }

    const routeDrainageDistance =
        0.0;

    final risk = _calculateRisk(
      rainfall: routeRainfall,
      elevation: routeElevation,
      drainageDistance:
          routeDrainageDistance,
    );

    double score = 0;

    switch (risk) {
      case RiskLevel.safe:
        score = 0;
        break;

      case RiskLevel.moderate:
        score = 2;
        break;

      case RiskLevel.impassable:
        score = 4;
        break;
    }

    return {
      'score': score,
      'rainfall': routeRainfall,
      'elevation': routeElevation,
      'drainageDistance':
          routeDrainageDistance,
      'risk': risk,
    };
  }

  // ==========================================================
  // LOAD SELECTED ROUTE RISK
  // ==========================================================

  Future<void> _loadRiskInformation(
    RouteOption route,
  ) async {
    try {
      rainfall =
          await WeatherService
              .getRouteRainfall(
        route.coordinates,
      );
    } catch (_) {
      rainfall = 0.0;
    }

    try {
      final elevations =
          await ElevationService
              .getElevations(
        route.coordinates,
      );

      if (elevations.isNotEmpty) {
        elevation =
            elevations.reduce(
                  (a, b) => a + b,
                ) /
                elevations.length;
      } else {
        elevation = 0.0;
      }
    } catch (_) {
      elevation = 0.0;
    }

    drainageDistance = 0.0;

    selectedRisk = _calculateRisk(
      rainfall: rainfall,
      elevation: elevation,
      drainageDistance:
          drainageDistance,
    );
  }

  // ==========================================================
  // RISK CALCULATION
  // ==========================================================

  RiskLevel _calculateRisk({
    required double rainfall,
    required double elevation,
    required double drainageDistance,
  }) {
    int riskScore = 0;

    if (rainfall >= 10) {
      riskScore += 2;
    } else if (rainfall >= 5) {
      riskScore += 1;
    }

    if (elevation < 5) {
      riskScore += 2;
    } else if (elevation < 15) {
      riskScore += 1;
    }

    if (drainageDistance > 1000) {
      riskScore += 2;
    } else if (drainageDistance > 500) {
      riskScore += 1;
    }

    if (riskScore >= 4) {
      return RiskLevel.impassable;
    }

    if (riskScore >= 2) {
      return RiskLevel.moderate;
    }

    return RiskLevel.safe;
  }

  // ==========================================================
  // FIT MAP TO ROUTE
  // ==========================================================

  void fitMapToRoute(
    RouteOption route,
  ) {
    if (route.coordinates.isEmpty) {
      return;
    }

    double minLat =
        route.coordinates.first[0];

    double maxLat =
        route.coordinates.first[0];

    double minLng =
        route.coordinates.first[1];

    double maxLng =
        route.coordinates.first[1];

    for (final point
        in route.coordinates) {
      minLat = math.min(
        minLat,
        point[0],
      );

      maxLat = math.max(
        maxLat,
        point[0],
      );

      minLng = math.min(
        minLng,
        point[1],
      );

      maxLng = math.max(
        maxLng,
        point[1],
      );
    }

    if (currentPosition != null) {
      minLat = math.min(
        minLat,
        currentPosition!.latitude,
      );

      maxLat = math.max(
        maxLat,
        currentPosition!.latitude,
      );

      minLng = math.min(
        minLng,
        currentPosition!.longitude,
      );

      maxLng = math.max(
        maxLng,
        currentPosition!.longitude,
      );
    }

    if (destination != null) {
      minLat = math.min(
        minLat,
        destination!.latitude,
      );

      maxLat = math.max(
        maxLat,
        destination!.latitude,
      );

      minLng = math.min(
        minLng,
        destination!.longitude,
      );

      maxLng = math.max(
        maxLng,
        destination!.longitude,
      );
    }

    final center = LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );

    mapController.move(
      center,
      calculateZoom(),
    );
  }

  // ==========================================================
  // CALCULATE ZOOM
  // ==========================================================

  double calculateZoom() {
    if (currentPosition == null ||
        destination == null) {
      return 14;
    }

    final distance =
        Geolocator.distanceBetween(
      currentPosition!.latitude,
      currentPosition!.longitude,
      destination!.latitude,
      destination!.longitude,
    );

    if (distance < 500) return 16;
    if (distance < 1000) return 15;
    if (distance < 3000) return 14;
    if (distance < 7000) return 12.8;
    if (distance < 15000) return 11.5;

    return 10;
  }

  // ==========================================================
  // ROUTE POINTS
  // ==========================================================

  List<LatLng> _routePoints(
    RouteOption route,
  ) {
    return route.coordinates.map(
      (point) {
        return LatLng(
          point[0],
          point[1],
        );
      },
    ).toList();
  }

  // ==========================================================
  // SELECT ROUTE
  // ==========================================================

  Future<void> _selectRoute(
    int index,
  ) async {
    if (index < 0 ||
        index >= routes.length) {
      return;
    }

    setState(() {
      selectedRouteIndex = index;
    });

    await _loadRiskInformation(
      routes[index],
    );

    if (!mounted) return;

    setState(() {});

    fitMapToRoute(
      routes[index],
    );

    // Speak selected route.
    await _speakRouteSummary(
      routes[index],
    );
  }

  // ==========================================================
  // FORMAT DURATION
  // ==========================================================

  String _formatDuration(
    double seconds,
  ) {
    final minutes =
        (seconds / 60).round();

    if (minutes < 60) {
      return '$minutes min';
    }

    final hours =
        minutes ~/ 60;

    final remainingMinutes =
        minutes % 60;

    if (remainingMinutes == 0) {
      return '$hours hr';
    }

    return '$hours hr '
        '$remainingMinutes min';
  }

  // ==========================================================
  // FORMAT DISTANCE
  // ==========================================================

  String _formatDistance(
    double meters,
  ) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }

    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  // ==========================================================
  // RISK TEXT
  // ==========================================================

  String _riskText(
    RiskLevel risk,
  ) {
    switch (risk) {
      case RiskLevel.safe:
        return 'Safe';

      case RiskLevel.moderate:
        return 'Moderate';

      case RiskLevel.impassable:
        return 'High Risk';
    }
  }

  // ==========================================================
  // RISK COLOR
  // ==========================================================

  Color _riskColor(
    RiskLevel risk,
  ) {
    switch (risk) {
      case RiskLevel.safe:
        return const Color(0xFF16A34A);

      case RiskLevel.moderate:
        return const Color(0xFFF59E0B);

      case RiskLevel.impassable:
        return const Color(0xFFDC2626);
    }
  }

  // ==========================================================
  // MODE ICON
  // ==========================================================

  IconData _modeIcon() {
    switch (
        widget.travelMode.toLowerCase()) {
      case 'bike':
        return Icons.two_wheeler;

      case 'bus':
        return Icons.directions_bus;

      case 'walking':
        return Icons.directions_walk;

      case 'ambulance':
        return Icons.local_hospital;

      case 'rescue':
        return Icons.emergency;

      case 'car':
      default:
        return Icons.directions_car;
    }
  }

  // ==========================================================
  // MODE TITLE
  // ==========================================================

  String _modeTitle() {
    if (isAmbulance) {
      return 'Ambulance Emergency';
    }

    if (isRescue) {
      return 'Rescue Mode';
    }

    return '${widget.travelMode} Mode';
  }

  // ==========================================================
  // SHOW MESSAGE
  // ==========================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior:
              SnackBarBehavior.floating,
          backgroundColor:
              darkColor,
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(12),
          ),
        ),
      );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      extendBodyBehindAppBar: true,

      appBar: AppBar(
        elevation: 0,
        backgroundColor:
            Colors.black.withOpacity(0.15),
        foregroundColor:
            Colors.white,

        title: Row(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              _modeIcon(),
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              _modeTitle(),
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),

        centerTitle: true,
      ),

      body: Stack(
        children: [
          // ==================================================
          // MAP
          // ==================================================

          FlutterMap(
            mapController:
                mapController,

            options: MapOptions(
              initialCenter:
                  const LatLng(
                13.0827,
                80.2707,
              ),

              initialZoom: 12,

              onTap: _onMapTap,
            ),

            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/'
                    '{z}/{x}/{y}.png',

                userAgentPackageName:
                    'com.example.hydropulse',
              ),

              if (routes.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (
                      int i = 0;
                      i < routes.length;
                      i++
                    )
                      Polyline(
                        points:
                            _routePoints(
                          routes[i],
                        ),

                        strokeWidth:
                            i ==
                                    selectedRouteIndex
                                ? 6
                                : 4,

                        color:
                            i ==
                                    selectedRouteIndex
                                ? primaryColor
                                : Colors
                                    .grey
                                    .shade400,
                      ),
                  ],
                ),

              MarkerLayer(
                markers: [
                  if (currentPosition != null)
                    Marker(
                      point: LatLng(
                        currentPosition!
                            .latitude,
                        currentPosition!
                            .longitude,
                      ),

                      width: 50,
                      height: 50,

                      child: Container(
                        decoration:
                            BoxDecoration(
                          gradient:
                              const LinearGradient(
                            begin:
                                Alignment.topLeft,
                            end:
                                Alignment.bottomRight,
                            colors: [
                              Color(
                                0xFF3B82F6,
                              ),
                              darkColor,
                            ],
                          ),

                          shape:
                              BoxShape.circle,

                          border:
                              Border.all(
                            color:
                                Colors.white,
                            width: 3,
                          ),

                          boxShadow: [
                            BoxShadow(
                              color:
                                  primaryColor
                                      .withOpacity(
                                0.5,
                              ),
                              blurRadius: 10,
                              offset:
                                  const Offset(
                                0,
                                4,
                              ),
                            ),
                          ],
                        ),

                        child:
                            const Icon(
                          Icons.my_location,
                          color:
                              Colors.white,
                          size: 24,
                        ),
                      ),
                    ),

                  if (destination != null)
                    Marker(
                      point:
                          destination!,

                      width: 55,
                      height: 55,

                      child: Container(
                        decoration:
                            BoxDecoration(
                          shape:
                              BoxShape.circle,

                          color: isAmbulance
                              ? Colors.white
                              : Colors.transparent,

                          boxShadow: [
                            if (isAmbulance)
                              BoxShadow(
                                color:
                                    Colors.red
                                        .withOpacity(
                                  0.25,
                                ),
                                blurRadius: 12,
                              ),
                          ],
                        ),

                        child: Icon(
                          isAmbulance
                              ? Icons
                                  .local_hospital
                              : Icons
                                  .location_pin,

                          color:
                              const Color(
                            0xFFDC2626,
                          ),

                          size: 48,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // ==================================================
          // TOP CARD
          // ==================================================

          Positioned(
            top: 100,
            left: 14,
            right: 14,

            child: Container(
              decoration:
                  BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(
                  18,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withOpacity(
                      0.08,
                    ),
                    blurRadius: 16,
                    offset:
                        const Offset(
                      0,
                      6,
                    ),
                  ),
                ],
              ),

              child: Padding(
                padding:
                    const EdgeInsets.all(
                  14,
                ),

                child: Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.all(
                        8,
                      ),

                      decoration:
                          BoxDecoration(
                        color:
                            primaryColor
                                .withOpacity(
                          0.1,
                        ),
                        shape:
                            BoxShape.circle,
                      ),

                      child: Icon(
                        isAmbulance
                            ? Icons
                                .local_hospital
                            : isRescue
                                ? Icons
                                    .emergency
                                : Icons
                                    .water_drop,

                        color:
                            primaryColor,

                        size: 20,
                      ),
                    ),

                    const SizedBox(
                      width: 12,
                    ),

                    Expanded(
                      child: Text(
                        _topCardText(),

                        maxLines: 2,

                        overflow:
                            TextOverflow
                                .ellipsis,

                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.w600,
                          color: Color(
                            0xFF1E293B,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ==================================================
          // VOICE BUTTON
          // ==================================================

          Positioned(
            right: 15,

            bottom:
                routes.isEmpty
                    ? 215
                    : 415,

            child: Container(
              decoration:
                  BoxDecoration(
                shape:
                    BoxShape.circle,

                boxShadow: [
                  BoxShadow(
                    color:
                        primaryColor
                            .withOpacity(
                      0.30,
                    ),
                    blurRadius: 14,
                    offset:
                        const Offset(
                      0,
                      6,
                    ),
                  ),
                ],
              ),

              child:
                  FloatingActionButton(
                heroTag:
                    'voiceButton',

                backgroundColor:
                    voiceEnabled
                        ? primaryColor
                        : Colors.white,

                foregroundColor:
                    voiceEnabled
                        ? Colors.white
                        : primaryColor,

                onPressed:
                    _toggleVoice,

                child: Icon(
                  voiceEnabled
                      ? Icons.volume_up
                      : Icons.volume_off,
                ),
              ),
            ),
          ),

          // ==================================================
          // LOCATION BUTTON
          // ==================================================

          Positioned(
            right: 15,

            bottom:
                routes.isEmpty
                    ? 150
                    : 350,

            child: Container(
              decoration:
                  BoxDecoration(
                shape:
                    BoxShape.circle,

                boxShadow: [
                  BoxShadow(
                    color:
                        primaryColor
                            .withOpacity(
                      0.35,
                    ),
                    blurRadius: 14,
                    offset:
                        const Offset(
                      0,
                      6,
                    ),
                  ),
                ],
              ),

              child:
                  FloatingActionButton(
                heroTag:
                    'locationButton',

                backgroundColor:
                    Colors.white,

                foregroundColor:
                    primaryColor,

                onPressed:
                    loadingLocation
                        ? null
                        : _getCurrentLocation,

                child:
                    loadingLocation
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                              color:
                                  primaryColor,
                            ),
                          )
                        : const Icon(
                            Icons.my_location,
                          ),
              ),
            ),
          ),

          // ==================================================
          // BOTTOM PANEL
          // ==================================================

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,

            child:
                _buildBottomPanel(),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // TOP CARD TEXT
  // ==========================================================

  String _topCardText() {
    if (isAmbulance) {
      if (searchingHospitals) {
        return 'Finding nearest suitable hospital...';
      }

      if (selectedHospitalName != null) {
        return selectedHospitalName!;
      }

      return 'Ambulance mode: hospital will be selected automatically';
    }

    if (isRescue) {
      return destination == null
          ? 'Tap on the map to select the rescue destination'
          : destinationAddress ??
              'Rescue destination selected';
    }

    return destination == null
        ? 'Tap on the map to select a destination'
        : destinationAddress ??
            'Destination selected';
  }

  // ==========================================================
  // BOTTOM PANEL
  // ==========================================================

  Widget _buildBottomPanel() {
    return SafeArea(
      top: false,

      child: Container(
        decoration:
            const BoxDecoration(
          color: Colors.white,

          borderRadius:
              BorderRadius.vertical(
            top:
                Radius.circular(28),
          ),

          boxShadow: [
            BoxShadow(
              blurRadius: 20,
              offset:
                  Offset(0, -6),
              color: Colors.black12,
            ),
          ],
        ),

        padding:
            const EdgeInsets.fromLTRB(
          18,
          18,
          18,
          14,
        ),

        child: Column(
          mainAxisSize:
              MainAxisSize.min,

          children: [
            Container(
              width: 40,
              height: 4,
              margin:
                  const EdgeInsets.only(
                bottom: 14,
              ),

              decoration:
                  BoxDecoration(
                color:
                    Colors.grey.shade300,
                borderRadius:
                    BorderRadius.circular(
                  4,
                ),
              ),
            ),

            if (isAmbulance)
              _buildAmbulanceCard()
            else
              _buildNormalDestinationCard(),

            const SizedBox(
              height: 14,
            ),

            SizedBox(
              width:
                  double.infinity,

              height: 54,

              child:
                  DecoratedBox(
                decoration:
                    BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(
                    16,
                  ),

                  gradient:
                      const LinearGradient(
                    begin:
                        Alignment.centerLeft,
                    end:
                        Alignment.centerRight,
                    colors: [
                      Color(
                        0xFF3B82F6,
                      ),
                      darkColor,
                    ],
                  ),

                  boxShadow: [
                    BoxShadow(
                      color:
                          primaryColor
                              .withOpacity(
                        0.35,
                      ),
                      blurRadius: 16,
                      offset:
                          const Offset(
                        0,
                        8,
                      ),
                    ),
                  ],
                ),

                child: Material(
                  color:
                      Colors.transparent,

                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(
                      16,
                    ),

                    onTap:
                        loadingRoutes
                            ? null
                            : _findSafestRoute,

                    child:
                        Center(
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .center,

                        children: [
                          if (loadingRoutes)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                                color:
                                    Colors.white,
                              ),
                            )
                          else
                            Icon(
                              isAmbulance
                                  ? Icons
                                      .local_hospital
                                  : Icons.route,
                              color:
                                  Colors.white,
                              size: 20,
                            ),

                          const SizedBox(
                            width: 10,
                          ),

                          Text(
                            _routeButtonText(),

                            style:
                                const TextStyle(
                              color:
                                  Colors.white,
                              fontWeight:
                                  FontWeight.bold,
                              fontSize:
                                  16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            if (routes.isNotEmpty) ...[
              const SizedBox(
                height: 16,
              ),

              Row(
                children: [
                  Text(
                    isAmbulance
                        ? 'Hospital Routes'
                        : 'Available Routes',

                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 16,
                      color:
                          Color(
                        0xFF1E293B,
                      ),
                    ),
                  ),

                  const Spacer(),

                  Container(
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),

                    decoration:
                        BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(
                        20,
                      ),

                      color:
                          _riskColor(
                        selectedRisk,
                      ).withOpacity(
                        0.12,
                      ),
                    ),

                    child: Text(
                      _riskText(
                        selectedRisk,
                      ),

                      style:
                          TextStyle(
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 12,
                        color:
                            _riskColor(
                          selectedRisk,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 10,
              ),

              SizedBox(
                height: 115,

                child:
                    ListView.builder(
                  scrollDirection:
                      Axis.horizontal,

                  itemCount:
                      routes.length,

                  itemBuilder:
                      (
                    context,
                    index,
                  ) {
                    return _buildRouteCard(
                      routes[index],
                      index,
                    );
                  },
                ),
              ),

              if (routes[
                      selectedRouteIndex]
                  .steps
                  .isNotEmpty)
                _buildDirections(
                  routes[
                      selectedRouteIndex],
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // AMBULANCE CARD
  // ==========================================================

  Widget _buildAmbulanceCard() {
    return Container(
      width: double.infinity,

      padding:
          const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color:
            const Color(0xFFFEF2F2),

        borderRadius:
            BorderRadius.circular(
          18,
        ),

        border: Border.all(
          color:
              const Color(
            0xFFFECACA,
          ),
        ),
      ),

      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,

            decoration:
                const BoxDecoration(
              shape:
                  BoxShape.circle,
              color:
                  Color(0xFFFEE2E2),
            ),

            child:
                const Icon(
              Icons.local_hospital,
              color:
                  Color(0xFFDC2626),
              size: 25,
            ),
          ),

          const SizedBox(
            width: 12,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                const Text(
                  'Emergency Hospital',

                  style:
                      TextStyle(
                    fontSize: 12,
                    color:
                        Color(0xFF991B1B),
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),

                const SizedBox(
                  height: 3,
                ),

                Text(
                  searchingHospitals
                      ? 'Finding best hospital...'
                      : selectedHospitalName ??
                          'Hospital not selected',

                  maxLines: 2,

                  overflow:
                      TextOverflow.ellipsis,

                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                    fontSize: 16,
                    color:
                        Color(0xFF1E293B),
                  ),
                ),

                if (selectedHospitalDistance !=
                    null) ...[
                  const SizedBox(
                    height: 4,
                  ),

                  Text(
                    '${_formatDistance(selectedHospitalDistance!)} • ${routes.isNotEmpty ? _formatDuration(routes[selectedRouteIndex].durationSeconds) : '--'}',

                    style:
                        TextStyle(
                      fontSize: 12,
                      color:
                          Colors.grey.shade700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // NORMAL DESTINATION CARD
  // ==========================================================

  Widget _buildNormalDestinationCard() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,

          decoration:
              BoxDecoration(
            color:
                primaryColor.withOpacity(
              0.10,
            ),

            shape:
                BoxShape.circle,
          ),

          child:
              const Icon(
            Icons.location_on,
            color:
                primaryColor,
          ),
        ),

        const SizedBox(
          width: 12,
        ),

        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [
              Text(
                isRescue
                    ? 'Rescue Destination'
                    : 'Destination',

                style:
                    TextStyle(
                  fontSize: 12,
                  color:
                      Colors.grey.shade600,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),

              Text(
                destination == null
                    ? 'Not selected'
                    : destinationAddress ??
                        'Selected destination',

                maxLines: 2,

                overflow:
                    TextOverflow.ellipsis,

                style:
                    const TextStyle(
                  fontWeight:
                      FontWeight.bold,
                  color:
                      Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // ROUTE BUTTON TEXT
  // ==========================================================

  String _routeButtonText() {
    if (loadingRoutes) {
      if (isAmbulance) {
        return 'Finding emergency route...';
      }

      return 'Analyzing live data...';
    }

    if (isAmbulance) {
      return 'Find Best Hospital Route';
    }

    if (isRescue) {
      return 'Find Safest Rescue Route';
    }

    return 'Find Safest Route';
  }

  // ==========================================================
  // ROUTE CARD
  // ==========================================================

  Widget _buildRouteCard(
    RouteOption route,
    int index,
  ) {
    final selected =
        index == selectedRouteIndex;

    return GestureDetector(
      onTap: () {
        _selectRoute(index);
      },

      child:
          AnimatedContainer(
        duration:
            const Duration(
          milliseconds: 200,
        ),

        width: 210,

        margin:
            const EdgeInsets.only(
          right: 10,
        ),

        padding:
            const EdgeInsets.all(
          14,
        ),

        decoration:
            BoxDecoration(
          borderRadius:
              BorderRadius.circular(
            18,
          ),

          border:
              Border.all(
            color: selected
                ? Colors.transparent
                : Colors.grey.shade200,
            width: 1.2,
          ),

          gradient: selected
              ? const LinearGradient(
                  begin:
                      Alignment.topLeft,
                  end:
                      Alignment.bottomRight,
                  colors: [
                    Color(
                      0xFF3B82F6,
                    ),
                    darkColor,
                  ],
                )
              : null,

          color: selected
              ? null
              : Colors.white,

          boxShadow: [
            BoxShadow(
              color: selected
                  ? primaryColor
                      .withOpacity(
                      0.30,
                    )
                  : Colors.black
                      .withOpacity(
                      0.04,
                    ),
              blurRadius:
                  selected ? 14 : 6,
              offset: Offset(
                0,
                selected ? 8 : 2,
              ),
            ),
          ],
        ),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons
                          .radio_button_checked
                      : Icons
                          .radio_button_off,

                  color: selected
                      ? Colors.white
                      : Colors.grey,

                  size: 20,
                ),

                const SizedBox(
                  width: 6,
                ),

                Expanded(
                  child: Text(
                    selected
                        ? isAmbulance
                            ? 'Best Emergency Route'
                            : 'Safest Route'
                        : 'Route ${index + 1}',

                    overflow:
                        TextOverflow.ellipsis,

                    style:
                        TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      color: selected
                          ? Colors.white
                          : const Color(
                              0xFF1E293B,
                            ),
                    ),
                  ),
                ),
              ],
            ),

            const Spacer(),

            Row(
              children: [
                Icon(
                  Icons.route,
                  size: 18,
                  color: selected
                      ? Colors.white
                          .withOpacity(
                          0.9,
                        )
                      : Colors.grey
                          .shade700,
                ),

                const SizedBox(
                  width: 5,
                ),

                Text(
                  _formatDistance(
                    route.distanceMeters,
                  ),

                  style:
                      TextStyle(
                    color: selected
                        ? Colors.white
                        : const Color(
                            0xFF1E293B,
                          ),
                    fontSize: 13,
                  ),
                ),

                const SizedBox(
                  width: 12,
                ),

                Icon(
                  Icons.access_time,
                  size: 18,
                  color: selected
                      ? Colors.white
                          .withOpacity(
                          0.9,
                        )
                      : Colors.grey
                          .shade700,
                ),

                const SizedBox(
                  width: 5,
                ),

                Text(
                  _formatDuration(
                    route.durationSeconds,
                  ),

                  style:
                      TextStyle(
                    color: selected
                        ? Colors.white
                        : const Color(
                            0xFF1E293B,
                          ),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // DIRECTIONS
  // ==========================================================

  Widget _buildDirections(
    RouteOption route,
  ) {
    return Theme(
      data:
          Theme.of(context).copyWith(
        dividerColor:
            Colors.transparent,
      ),

      child:
          ExpansionTile(
        tilePadding:
            EdgeInsets.zero,

        iconColor:
            primaryColor,

        collapsedIconColor:
            primaryColor,

        title:
            Row(
          children: [
            const Expanded(
              child: Text(
                'Directions',
                style:
                    TextStyle(
                  fontWeight:
                      FontWeight.bold,
                  color:
                      Color(0xFF1E293B),
                ),
              ),
            ),

            IconButton(
              tooltip:
                  'Read directions',
              icon:
                  const Icon(
                Icons.volume_up,
                color:
                    primaryColor,
              ),
              onPressed:
                  () {
                _speakDirections(
                  route,
                );
              },
            ),
          ],
        ),

        children: [
          SizedBox(
            height: 160,

            child:
                ListView.builder(
              itemCount:
                  route.steps.length,

              itemBuilder:
                  (
                context,
                index,
              ) {
                final step =
                    route.steps[index];

                return ListTile(
                  dense: true,

                  leading:
                      CircleAvatar(
                    radius: 15,

                    backgroundColor:
                        primaryColor
                            .withOpacity(
                      0.1,
                    ),

                    foregroundColor:
                        primaryColor,

                    child:
                        Text(
                      '${index + 1}',

                      style:
                          const TextStyle(
                        fontSize: 12,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),

                  title:
                      Text(
                    step.instruction,

                    style:
                        const TextStyle(
                      fontSize: 13,
                    ),
                  ),

                  trailing:
                      Text(
                    step.formattedDistance,

                    style:
                        const TextStyle(
                      fontSize: 12,
                      color:
                          Colors.grey,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    VoiceService.instance.stop();
    super.dispose();
  }
}