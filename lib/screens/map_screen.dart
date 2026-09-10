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

// ============================================================
// DEMO ROAD CONDITIONS
// ============================================================

enum DemoRoadCondition {
  dry,
  puddle,
  flood,
}

// ============================================================
// ROUTE SEGMENT
// ============================================================

class _RouteSegment {
  final LatLng start;
  final LatLng end;
  final RiskLevel risk;
  final DemoRoadCondition condition;

  const _RouteSegment({
    required this.start,
    required this.end,
    required this.risk,
    required this.condition,
  });
}

// ============================================================
// AI ROUTE DATA
// ============================================================

class _AiRoute {
  final String routeId;
  final String name;
  final double distanceKm;
  final int estimatedMinutes;
  final String status;
  final String colorHex;
  final bool recommended;
  final String hazardLabel;
  final double confidence;
  final String severity;
  final bool passable;
  final String advisory;
  final List<LatLng> points;

  const _AiRoute({
    required this.routeId,
    required this.name,
    required this.distanceKm,
    required this.estimatedMinutes,
    required this.status,
    required this.colorHex,
    required this.recommended,
    required this.hazardLabel,
    required this.confidence,
    required this.severity,
    required this.passable,
    required this.advisory,
    required this.points,
  });
}

// ============================================================
// MAP SCREEN
// ============================================================

class MapScreen extends StatefulWidget {
  final String travelMode;
  final bool selectionMode;

  const MapScreen({
    super.key,
    required this.travelMode,
    this.selectionMode = false,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

// ============================================================
// STATE
// ============================================================

class _MapScreenState extends State<MapScreen> {
  final MapController mapController = MapController();
  final TextEditingController _searchController =
      TextEditingController();

  Position? currentPosition;

  LatLng? destination;
  String? destinationAddress;

  bool loadingAddress = false;
  bool loadingLocation = false;
  bool loadingRoutes = false;
  bool searchingHospitals = false;

  bool voiceEnabled = true;
  bool speaking = false;

  String? errorMessage;

  List<RouteOption> routes = [];
  int selectedRouteIndex = 0;

  // AI routes returned by FastAPI.
  List<_AiRoute> aiRoutes = [];
  int aiSelectedRouteIndex = 0;

  // ==========================================================
  // DEMO ROUTE DATA
  // ==========================================================

  final Map<int, List<_RouteSegment>> routeSegments = {};
  final Map<int, RiskLevel> routeRiskLevels = {};

  // ==========================================================
  // LIVE RISK DATA
  // ==========================================================

  double rainfall = 0.0;
  double elevation = 0.0;
  double drainageDistance = 0.0;

  RiskLevel selectedRisk = RiskLevel.safe;

  // ==========================================================
  // HOSPITAL DATA
  // ==========================================================

  String? selectedHospitalName;
  String? selectedHospitalAddress;
  double? selectedHospitalDistance;
  double? selectedHospitalScore;

  // ==========================================================
  // MODE HELPERS
  // ==========================================================

  bool get isAmbulance =>
      widget.travelMode.toLowerCase().contains('ambulance');

  bool get isRescue =>
      widget.travelMode.toLowerCase().contains('rescue');

  bool get isEmergency =>
      isAmbulance || isRescue;

  static const Color primaryColor = Color(0xFF1565C0);

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ==========================================================
  // INITIALIZE LOCATION
  // ==========================================================

  Future<void> _initializeLocation() async {
    await _getCurrentLocation();

    if (isAmbulance && currentPosition != null) {
      await _findBestHospitalRoute();
    }
  }

  // ==========================================================
  // GET CURRENT LOCATION
  // ==========================================================

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;

    setState(() {
      loadingLocation = true;
      errorMessage = null;
    });

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
      debugPrint(
        'Location error: $e',
      );

      if (!mounted) return;

      setState(() {
        loadingLocation = false;
        errorMessage =
            'Unable to get current location';
      });

      _showMessage(
        'GPS unavailable. Demo location will be used for route search.',
      );
    }
  }

  // ==========================================================
  // SEARCH DESTINATION
  // ==========================================================

  Future<void> _searchDestination() async {
    final query =
        _searchController.text.trim();

    if (query.isEmpty) {
      _showMessage(
        'Enter a destination',
      );
      return;
    }

    FocusScope.of(context).unfocus();

    if (!mounted) return;

    setState(() {
      loadingAddress = true;
      loadingRoutes = true;

      errorMessage = null;

      aiRoutes.clear();
      aiSelectedRouteIndex = 0;

      routes.clear();
      routeSegments.clear();
      routeRiskLevels.clear();
    });

    try {
      // ========================================================
      // NOMINATIM SEARCH
      // ========================================================

      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=json'
        '&q=${Uri.encodeQueryComponent(query)}'
        '&limit=1'
        '&countrycodes=in',
      );

      debugPrint(
        'Searching destination: $query',
      );

      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'User-Agent':
              'HydroPulse Flutter App',
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Location search failed',
        );
      }

      final results =
          jsonDecode(response.body)
              as List<dynamic>;

      if (results.isEmpty) {
        throw Exception(
          'Destination not found',
        );
      }

      final place =
          results.first
              as Map<String, dynamic>;

      final lat =
          double.parse(
        place['lat'].toString(),
      );

      final lng =
          double.parse(
        place['lon'].toString(),
      );

      final displayName =
          place['display_name']
                  ?.toString() ??
              query;

      // ========================================================
      // SET DESTINATION
      // ========================================================

      if (!mounted) return;

      setState(() {
        destination =
            LatLng(lat, lng);

        destinationAddress =
            displayName;

        loadingAddress = false;

        routes.clear();
        routeSegments.clear();
        routeRiskLevels.clear();

        aiRoutes.clear();
        aiSelectedRouteIndex = 0;
      });

      // Move to searched destination.
      mapController.move(
        LatLng(lat, lng),
        13,
      );

      // ========================================================
      // LOAD SAFE ROUTES
      // ========================================================

      await _loadAiRoutes(
        destinationName: query,
      );
    } catch (e) {
      debugPrint(
        'Destination search error: $e',
      );

      if (!mounted) return;

      setState(() {
        loadingAddress = false;
        loadingRoutes = false;
        errorMessage =
            'Destination not found';
      });

      _showMessage(
        'Destination not found: $query',
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
        'Ambulance mode automatically selects the best nearby hospital.',
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      destination = point;

      destinationAddress =
          'Finding location...';

      loadingAddress = true;
      loadingRoutes = false;

      routes.clear();
      routeSegments.clear();
      routeRiskLevels.clear();

      aiRoutes.clear();
      aiSelectedRouteIndex = 0;

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

      if (response.statusCode != 200) {
        throw Exception(
          'Reverse geocoding failed',
        );
      }

      final data =
          jsonDecode(response.body);

      final displayName =
          data['display_name']
              ?.toString();

      if (!mounted) return;

      setState(() {
        destinationAddress =
            displayName ??
                'Selected destination';

        loadingAddress = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        destinationAddress =
            '${point.latitude.toStringAsFixed(5)}, '
            '${point.longitude.toStringAsFixed(5)}';

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

    if (destination == null) {
      _showMessage(
        'Search or select a destination first',
      );
      return;
    }

    await _loadAiRoutes(
      destinationName:
          destinationAddress,
    );
  }

  // ==========================================================
  // LOAD AI ROUTES FROM FASTAPI
  // ==========================================================

  Future<void> _loadAiRoutes({
    String? destinationName,
  }) async {
    if (destination == null) {
      _showMessage(
        'Please search for a destination first',
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      loadingRoutes = true;
      errorMessage = null;

      aiRoutes.clear();
      aiSelectedRouteIndex = 0;
    });

    try {
      // ========================================================
      // CURRENT LOCATION
      // ========================================================

      // Use real GPS when available.
      //
      // If browser GPS is unavailable, use this demo origin.
      // This prevents the demo from stopping.
      final double userLat =
          currentPosition?.latitude ??
              10.8250;

      final double userLng =
          currentPosition?.longitude ??
              78.6900;

      // ========================================================
      // DESTINATION
      // ========================================================

      final double destLat =
          destination!.latitude;

      final double destLng =
          destination!.longitude;

      final String destName =
          destinationName ??
              destinationAddress ??
              'Selected destination';

      // ========================================================
      // FASTAPI URL
      // ========================================================

      final url = Uri.parse(
        'http://192.168.14.139:8000'
        '/api/route-hazard-navigation'
        '?user_lat=$userLat'
        '&user_lng=$userLng'
        '&dest_lat=$destLat'
        '&dest_lng=$destLng'
        '&dest_name=${Uri.encodeQueryComponent(destName)}',
      );

      debugPrint(
        'HydroPulse AI request: $url',
      );

      final response =
          await http.get(
        url,
        headers: {
          'Accept':
              'application/json',
        },
      );

      debugPrint(
        'HydroPulse AI response: '
        '${response.statusCode}',
      );

      if (response.statusCode != 200) {
        throw Exception(
          'AI server returned '
          '${response.statusCode}',
        );
      }

      // ========================================================
      // DECODE RESPONSE
      // ========================================================

      final data =
          jsonDecode(response.body)
              as Map<String, dynamic>;

      final navigation =
          data['navigation_summary']
              as Map<String, dynamic>;

      final destinationData =
          navigation['destination']
              as Map<String, dynamic>;

      final aiDestination =
          LatLng(
        (destinationData['lat']
                as num)
            .toDouble(),
        (destinationData['lng']
                as num)
            .toDouble(),
      );

      final routeData =
          (data['routes']
                  as List<dynamic>? ??
              []);

      final loadedRoutes =
          <_AiRoute>[];

      // ========================================================
      // PARSE EACH ROUTE
      // ========================================================

      for (final item
          in routeData) {
        final route =
            item as Map<String, dynamic>;

        final hazard =
            route['ai_hazard_detection']
                    as Map<String, dynamic>? ??
                {};

        final coordinateData =
            route['path_coordinates']
                    as List<dynamic>? ??
                [];

        final points =
            <LatLng>[];

        for (final point
            in coordinateData) {
          if (point
              is! Map<String, dynamic>) {
            continue;
          }

          final latValue =
              point['lat'];

          final lngValue =
              point['lng'];

          if (latValue == null ||
              lngValue == null) {
            continue;
          }

          final lat =
              _toDouble(latValue);

          final lng =
              _toDouble(lngValue);

          points.add(
            LatLng(lat, lng),
          );
        }

        if (points.length < 2) {
          continue;
        }

        loadedRoutes.add(
          _AiRoute(
            routeId:
                route['route_id']
                        ?.toString() ??
                    'route_${loadedRoutes.length + 1}',

            name:
                route['name']
                        ?.toString() ??
                    'Route ${loadedRoutes.length + 1}',

            distanceKm:
                _toDouble(
              route['distance_km'],
            ),

            estimatedMinutes:
                _toInt(
              route['estimated_mins'],
            ),

            status:
                route['route_status']
                        ?.toString() ??
                    'UNKNOWN',

            colorHex:
                route['polyline_color']
                        ?.toString() ??
                    '#2196F3',

            recommended:
                route['is_recommended'] ==
                    true,

            hazardLabel:
                hazard['detected_label']
                        ?.toString()
                        .toUpperCase() ??
                    'UNKNOWN',

            confidence:
                _toDouble(
              hazard['confidence'],
            ),

            severity:
                hazard['severity']
                        ?.toString() ??
                    'UNKNOWN',

            passable:
                hazard['passable'] ==
                    true,

            advisory:
                hazard['advisory']
                        ?.toString() ??
                    'Drive carefully.',

            points: points,
          ),
        );
      }

      if (loadedRoutes.isEmpty) {
        throw Exception(
          'No valid AI routes found',
        );
      }

      // ========================================================
      // FIND RECOMMENDED ROUTE
      // ========================================================

      int recommendedIndex =
          loadedRoutes.indexWhere(
        (route) =>
            route.recommended,
      );

      if (recommendedIndex < 0) {
        recommendedIndex = 0;

        for (
          int i = 0;
          i < loadedRoutes.length;
          i++
        ) {
          if (_aiRiskRank(
                loadedRoutes[i],
              ) <
              _aiRiskRank(
                loadedRoutes[
                    recommendedIndex],
              )) {
            recommendedIndex = i;
          }
        }
      }

      // ========================================================
      // UPDATE SCREEN
      // ========================================================

      if (!mounted) return;

      setState(() {
        aiRoutes =
            loadedRoutes;

        aiSelectedRouteIndex =
            recommendedIndex;

        destination =
            aiDestination;

        destinationAddress =
            destinationData['name']
                    ?.toString() ??
                destName;

        routes.clear();

        routeSegments.clear();
        routeRiskLevels.clear();

        selectedRisk =
            _aiRiskLevel(
          loadedRoutes[
              recommendedIndex],
        );

        rainfall = 0.0;
        elevation = 0.0;
        drainageDistance = 0.0;

        loadingRoutes = false;
      });

      // Fit all routes.
      _fitAiRoutesOnMap();

      // ========================================================
      // MESSAGE
      // ========================================================

      final recommended =
          loadedRoutes[
              recommendedIndex];

      _showMessage(
        'Safest route: '
        '${recommended.name} • '
        '${_aiRiskText(recommended)}',
      );

      await _speakAiRouteSummary(
        recommended,
      );
    } catch (e) {
      debugPrint(
        'AI route error: $e',
      );

      if (!mounted) return;

      setState(() {
        loadingRoutes = false;

        errorMessage =
            'Unable to connect to HydroPulse AI server';
      });

      _showMessage(
        'Unable to connect to HydroPulse AI server',
      );
    }
  }

  // ==========================================================
  // NUMBER HELPERS
  // ==========================================================

  double _toDouble(
    dynamic value,
  ) {
    if (value == null) {
      return 0.0;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value.toString(),
        ) ??
        0.0;
  }

  int _toInt(
    dynamic value,
  ) {
    if (value == null) {
      return 0;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.round();
    }

    return int.tryParse(
          value.toString(),
        ) ??
        0;
  }

  // ==========================================================
  // AI RISK RANK
  // ==========================================================

  int _aiRiskRank(
    _AiRoute route,
  ) {
    final label =
        route.hazardLabel
            .toUpperCase();

    final severity =
        route.severity
            .toUpperCase();

    final status =
        route.status
            .toUpperCase();

    if (!route.passable ||
        label == 'FLOODED' ||
        severity == 'CRITICAL' ||
        status.contains('BLOCKED')) {
      return 2;
    }

    if (label == 'PUDDLE' ||
        severity == 'MODERATE' ||
        status.contains('MEDIUM') ||
        status.contains('HIGH_HAZARD')) {
      return 1;
    }

    return 0;
  }

  // ==========================================================
  // AI RISK LEVEL
  // ==========================================================

  RiskLevel _aiRiskLevel(
    _AiRoute route,
  ) {
    switch (_aiRiskRank(route)) {
      case 2:
        return RiskLevel.impassable;

      case 1:
        return RiskLevel.moderate;

      default:
        return RiskLevel.safe;
    }
  }

  // ==========================================================
  // AI RISK TEXT
  // ==========================================================

  String _aiRiskText(
    _AiRoute route,
  ) {
    return _riskText(
      _aiRiskLevel(route),
    );
  }

  // ==========================================================
  // AI ROUTE VOICE
  // ==========================================================

  Future<void> _speakAiRouteSummary(
    _AiRoute route,
  ) async {
    if (!voiceEnabled) return;

    try {
      if (mounted) {
        setState(() {
          speaking = true;
        });
      }

      final text =
          '${route.name}. '
          '${route.distanceKm.toStringAsFixed(1)} kilometers. '
          '${route.estimatedMinutes} minutes. '
          'Risk level is '
          '${_aiRiskText(route)}. '
          '${route.advisory}';

      await VoiceService.instance
          .speak(text);
    } catch (e) {
      debugPrint(
        'AI voice error: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          speaking = false;
        });
      }
    }
  }

  // ==========================================================
  // FIT AI ROUTES ON MAP
  // ==========================================================

  void _fitAiRoutesOnMap() {
    if (aiRoutes.isEmpty) {
      return;
    }

    final allPoints =
        <LatLng>[];

    for (final route
        in aiRoutes) {
      allPoints.addAll(
        route.points,
      );
    }

    if (currentPosition != null) {
      allPoints.add(
        LatLng(
          currentPosition!.latitude,
          currentPosition!.longitude,
        ),
      );
    }

    if (destination != null) {
      allPoints.add(
        destination!,
      );
    }

    if (allPoints.isEmpty) {
      return;
    }

    double minLat =
        allPoints.first.latitude;

    double maxLat =
        allPoints.first.latitude;

    double minLng =
        allPoints.first.longitude;

    double maxLng =
        allPoints.first.longitude;

    for (final point
        in allPoints) {
      minLat = math.min(
        minLat,
        point.latitude,
      );

      maxLat = math.max(
        maxLat,
        point.latitude,
      );

      minLng = math.min(
        minLng,
        point.longitude,
      );

      maxLng = math.max(
        maxLng,
        point.longitude,
      );
    }

    final center =
        LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );

    mapController.move(
      center,
      _calculateAiZoom(
        minLat,
        maxLat,
        minLng,
        maxLng,
      ),
    );
  }

  // ==========================================================
  // AI ZOOM
  // ==========================================================

  double _calculateAiZoom(
    double minLat,
    double maxLat,
    double minLng,
    double maxLng,
  ) {
    final latSpan =
        (maxLat - minLat).abs();

    final lngSpan =
        (maxLng - minLng).abs();

    final span =
        math.max(
      latSpan,
      lngSpan,
    );

    if (span < 0.003) {
      return 16;
    }

    if (span < 0.008) {
      return 15;
    }

    if (span < 0.015) {
      return 14;
    }

    if (span < 0.03) {
      return 13;
    }

    return 12;
  }

  // ==========================================================
  // AI ROUTE COLOR
  // ==========================================================

  Color _aiRouteColor(
    _AiRoute route,
  ) {
    final label =
        route.hazardLabel
            .toUpperCase();

    final severity =
        route.severity
            .toUpperCase();

    if (!route.passable ||
        label == 'FLOODED' ||
        severity == 'CRITICAL') {
      return Colors.red;
    }

    if (label == 'PUDDLE' ||
        severity == 'MODERATE' ||
        route.status
            .toUpperCase()
            .contains('MEDIUM') ||
        route.status
            .toUpperCase()
            .contains('HIGH_HAZARD')) {
      return Colors.orange;
    }

    return Colors.green;
  }

  // ==========================================================
  // AI ROUTE CARD
  // ==========================================================

  Widget _buildAiRouteCard(
    int index,
    _AiRoute route,
  ) {
    final selected =
        index ==
            aiSelectedRouteIndex;

    final risk =
        _aiRiskLevel(route);

    final riskColor =
        _riskColor(risk);

    return GestureDetector(
      onTap: () async {
        if (index < 0 ||
            index >= aiRoutes.length) {
          return;
        }

        setState(() {
          aiSelectedRouteIndex =
              index;

          selectedRisk =
              risk;
        });

        _fitAiRoutesOnMap();

        await _speakAiRouteSummary(
          route,
        );
      },
      child: AnimatedContainer(
        duration:
            const Duration(
          milliseconds: 200,
        ),
        width: 235,
        margin:
            const EdgeInsets.only(
          right: 12,
        ),
        padding:
            const EdgeInsets.all(14),
        decoration:
            BoxDecoration(
          color: selected
              ? primaryColor
              : Colors.white,
          borderRadius:
              BorderRadius.circular(
            18,
          ),
          border: Border.all(
            color: selected
                ? primaryColor
                : Colors.grey.shade300,
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 8,
              color: Colors.black
                  .withOpacity(0.08),
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
                  route.recommended
                      ? Icons.check_circle
                      : Icons.route,
                  color: selected
                      ? Colors.white
                      : _aiRouteColor(
                          route,
                        ),
                  size: 20,
                ),

                const SizedBox(
                  width: 8,
                ),

                Expanded(
                  child: Text(
                    'Route ${index + 1}',
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : Colors.black87,
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),

                if (route.recommended)
                  Container(
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration:
                        BoxDecoration(
                      color: selected
                          ? Colors.white
                              .withOpacity(
                              0.18,
                            )
                          : Colors.green
                              .withOpacity(
                              0.12,
                            ),
                      borderRadius:
                          BorderRadius.circular(
                        6,
                      ),
                    ),
                    child: Text(
                      'BEST',
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : Colors.green,
                        fontSize: 9,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              route.name,
              maxLines: 2,
              overflow:
                  TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Colors.black87,
                fontSize: 12,
                fontWeight:
                    FontWeight.w600,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            Row(
              children: [
                Icon(
                  Icons.straighten,
                  size: 15,
                  color: selected
                      ? Colors.white70
                      : Colors.grey,
                ),

                const SizedBox(
                  width: 4,
                ),

                Text(
                  '${route.distanceKm.toStringAsFixed(1)} km',
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : Colors.black87,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(
                  width: 10,
                ),

                Icon(
                  Icons.access_time,
                  size: 15,
                  color: selected
                      ? Colors.white70
                      : Colors.grey,
                ),

                const SizedBox(
                  width: 4,
                ),

                Text(
                  '${route.estimatedMinutes} min',
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : Colors.black87,
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 8,
            ),

            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration:
                      BoxDecoration(
                    color: selected
                        ? Colors.white
                            .withOpacity(
                            0.18,
                          )
                        : riskColor
                            .withOpacity(
                            0.12,
                          ),
                    borderRadius:
                        BorderRadius.circular(
                      8,
                    ),
                  ),
                  child: Text(
                    _riskText(risk),
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : riskColor,
                      fontSize: 11,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(
                  width: 6,
                ),

                Flexible(
                  child: Text(
                    route.hazardLabel,
                    overflow:
                        TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : _aiRouteColor(
                              route,
                            ),
                      fontSize: 10,
                      fontWeight:
                          FontWeight.bold,
                    ),
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
  // DEMO SEGMENTS
  // ==========================================================

  List<_RouteSegment>
      _buildDemoSegments(
    RouteOption route,
    int routeIndex,
    int totalRoutes,
  ) {
    final points =
        _routePoints(route);

    if (points.length < 2) {
      return [];
    }

    final segments =
        <_RouteSegment>[];

    final totalSegments =
        points.length - 1;

    for (int i = 0;
        i < totalSegments;
        i++) {
      final progress =
          i / totalSegments;

      DemoRoadCondition
          condition =
          DemoRoadCondition.dry;

      if (routeIndex == 0) {
        if (progress >= 0.25 &&
            progress <= 0.40) {
          condition =
              DemoRoadCondition.puddle;
        } else if (progress >= 0.58 &&
            progress <= 0.72) {
          condition =
              DemoRoadCondition.flood;
        }
      } else if (routeIndex == 1) {
        if (progress >= 0.40 &&
            progress <= 0.58) {
          condition =
              DemoRoadCondition.puddle;
        }
      } else if (routeIndex == 2) {
        condition =
            DemoRoadCondition.dry;
      }

      if (totalRoutes == 1) {
        if (progress >= 0.25 &&
            progress <= 0.38) {
          condition =
              DemoRoadCondition.puddle;
        } else if (progress >= 0.60 &&
            progress <= 0.75) {
          condition =
              DemoRoadCondition.flood;
        }
      }

      RiskLevel risk;

      switch (condition) {
        case DemoRoadCondition.dry:
          risk = RiskLevel.safe;
          break;

        case DemoRoadCondition.puddle:
          risk = RiskLevel.moderate;
          break;

        case DemoRoadCondition.flood:
          risk = RiskLevel.impassable;
          break;
      }

      segments.add(
        _RouteSegment(
          start: points[i],
          end: points[i + 1],
          risk: risk,
          condition: condition,
        ),
      );
    }

    return segments;
  }

  // ==========================================================
  // ROUTE POINTS
  // ==========================================================

  List<LatLng> _routePoints(
    RouteOption route,
  ) {
    return route.coordinates
        .map(
          (point) => LatLng(
            point[0],
            point[1],
          ),
        )
        .toList();
  }

  // ==========================================================
  // DEMO RISK
  // ==========================================================

  RiskLevel _riskFromDemoSegments(
    List<_RouteSegment> segments,
  ) {
    if (segments.any(
      (s) =>
          s.risk ==
          RiskLevel.impassable,
    )) {
      return RiskLevel.impassable;
    }

    if (segments.any(
      (s) =>
          s.risk ==
          RiskLevel.moderate,
    )) {
      return RiskLevel.moderate;
    }

    return RiskLevel.safe;
  }

  // ==========================================================
  // MERGE RISK
  // ==========================================================

  RiskLevel _mergeRisk(
    RiskLevel liveRisk,
    RiskLevel demoRisk,
  ) {
    if (liveRisk ==
            RiskLevel.impassable ||
        demoRisk ==
            RiskLevel.impassable) {
      return RiskLevel.impassable;
    }

    if (liveRisk ==
            RiskLevel.moderate ||
        demoRisk ==
            RiskLevel.moderate) {
      return RiskLevel.moderate;
    }

    return RiskLevel.safe;
  }

  // ==========================================================
  // CALCULATE LIVE ROUTE RISK
  // ==========================================================

  Future<_RouteRiskResult>
      _calculateRouteRisk(
    RouteOption route,
  ) async {
    double routeRainfall = 0.0;
    double routeElevation = 0.0;
    double routeDrainage = 0.0;

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

    routeDrainage = 0.0;

    final result =
        _calculateRisk(
      rainfall: routeRainfall,
      elevation: routeElevation,
      drainageDistance:
          routeDrainage,
    );

    return _RouteRiskResult(
      score: result.score,
      rainfall: routeRainfall,
      elevation: routeElevation,
      drainageDistance:
          routeDrainage,
      risk: result.risk,
    );
  }

  // ==========================================================
  // CALCULATE RISK
  // ==========================================================

  _RouteRiskResult _calculateRisk({
    required double rainfall,
    required double elevation,
    required double drainageDistance,
  }) {
    int score = 0;

    if (rainfall >= 10) {
      score += 2;
    } else if (rainfall >= 5) {
      score += 1;
    }

    if (elevation < 5) {
      score += 2;
    } else if (elevation < 15) {
      score += 1;
    }

    if (drainageDistance > 1000) {
      score += 2;
    } else if (drainageDistance > 500) {
      score += 1;
    }

    RiskLevel risk;

    if (score >= 4) {
      risk = RiskLevel.impassable;
    } else if (score >= 2) {
      risk = RiskLevel.moderate;
    } else {
      risk = RiskLevel.safe;
    }

    return _RouteRiskResult(
      score: score,
      rainfall: rainfall,
      elevation: elevation,
      drainageDistance:
          drainageDistance,
      risk: risk,
    );
  }

  // ==========================================================
  // LOAD RISK INFORMATION
  // ==========================================================

  Future<void> _loadRiskInformation(
    RouteOption route,
  ) async {
    try {
      final result =
          await _calculateRouteRisk(
        route,
      );

      if (!mounted) return;

      setState(() {
        rainfall =
            result.rainfall;

        elevation =
            result.elevation;

        drainageDistance =
            result.drainingDistance;

        selectedRisk =
            result.risk;
      });
    } catch (e) {
      debugPrint(
        'Risk loading error: $e',
      );
    }
  }

  // ==========================================================
  // SELECT OLD ROUTE
  // ==========================================================

  Future<void> _selectRoute(
    int index,
  ) async {
    if (index < 0 ||
        index >= routes.length) {
      return;
    }

    final route =
        routes[index];

    setState(() {
      selectedRouteIndex =
          index;
    });

    await _loadRiskInformation(
      route,
    );

    final demoRisk =
        routeRiskLevels[index] ??
            RiskLevel.safe;

    if (mounted) {
      setState(() {
        selectedRisk =
            _mergeRisk(
          selectedRisk,
          demoRisk,
        );
      });
    }

    fitMapToRoute(route);

    await _speakRouteSummary(
      route,
      selectedRisk,
    );
  }

  // ==========================================================
  // FIT OLD ROUTE
  // ==========================================================

  void fitMapToRoute(
    RouteOption route,
  ) {
    final points =
        _routePoints(route);

    if (points.isEmpty) {
      return;
    }

    double minLat =
        points.first.latitude;

    double maxLat =
        points.first.latitude;

    double minLng =
        points.first.longitude;

    double maxLng =
        points.first.longitude;

    for (final point
        in points) {
      minLat = math.min(
        minLat,
        point.latitude,
      );

      maxLat = math.max(
        maxLat,
        point.latitude,
      );

      minLng = math.min(
        minLng,
        point.longitude,
      );

      maxLng = math.max(
        maxLng,
        point.longitude,
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

    final center =
        LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );

    mapController.move(
      center,
      _calculateZoom(),
    );
  }

  // ==========================================================
  // CALCULATE ZOOM
  // ==========================================================

  double _calculateZoom() {
    if (currentPosition == null ||
        destination == null) {
      return 13;
    }

    final distance =
        Geolocator.distanceBetween(
      currentPosition!.latitude,
      currentPosition!.longitude,
      destination!.latitude,
      destination!.longitude,
    );

    if (distance < 500) {
      return 16;
    }

    if (distance < 1000) {
      return 15;
    }

    if (distance < 3000) {
      return 14;
    }

    if (distance < 7000) {
      return 12.8;
    }

    if (distance < 15000) {
      return 11.5;
    }

    return 10;
  }

  // ==========================================================
  // FIND NEARBY HOSPITALS
  // ==========================================================

  Future<List<Map<String, dynamic>>>
      _findNearbyHospitals() async {
    if (currentPosition == null) {
      return [];
    }

    try {
      final lat =
          currentPosition!.latitude;

      final lon =
          currentPosition!.longitude;

      final query = '''
[out:json];
(
  node["amenity"="hospital"](around:10000,$lat,$lon);
  way["amenity"="hospital"](around:10000,$lat,$lon);
  relation["amenity"="hospital"](around:10000,$lat,$lon);
);
out center tags;
''';

      final response =
          await http.post(
        Uri.parse(
          'https://overpass-api.de/api/interpreter',
        ),
        body: query,
      );

      if (response.statusCode !=
          200) {
        return [];
      }

      final data =
          jsonDecode(
        response.body,
      );

      final elements =
          data['elements'] as List;

      final hospitals =
          <Map<String, dynamic>>[];

      final seenNames =
          <String>{};

      for (final element
          in elements) {
        final tags =
            element['tags'] ?? {};

        final name =
            tags['name']
                ?.toString();

        if (name == null ||
            name.trim().isEmpty) {
          continue;
        }

        if (seenNames
            .contains(name)) {
          continue;
        }

        double? hospitalLat;
        double? hospitalLon;

        if (element['lat'] != null &&
            element['lon'] != null) {
          hospitalLat =
              (element['lat']
                      as num)
                  .toDouble();

          hospitalLon =
              (element['lon']
                      as num)
                  .toDouble();
        } else if (
            element['center'] !=
                null) {
          hospitalLat =
              (element['center']
                          ['lat']
                      as num)
                  .toDouble();

          hospitalLon =
              (element['center']
                          ['lon']
                      as num)
                  .toDouble();
        }

        if (hospitalLat ==
                null ||
            hospitalLon ==
                null) {
          continue;
        }

        final distance =
            Geolocator
                .distanceBetween(
          lat,
          lon,
          hospitalLat,
          hospitalLon,
        );

        hospitals.add({
          'name': name,
          'address':
              tags['addr:street'] ??
                  tags['addr:city'] ??
                  '',
          'latitude':
              hospitalLat,
          'longitude':
              hospitalLon,
          'distance':
              distance,
        });

        seenNames.add(name);

        if (hospitals.length >=
            5) {
          break;
        }
      }

      hospitals.sort(
        (a, b) =>
            (a['distance']
                    as double)
                .compareTo(
          b['distance']
              as double,
        ),
      );

      return hospitals;
    } catch (e) {
      debugPrint(
        'Hospital search error: $e',
      );

      return [];
    }
  }

  // ==========================================================
  // BEST HOSPITAL ROUTE
  // ==========================================================

  Future<void>
      _findBestHospitalRoute() async {
    if (currentPosition == null) {
      return;
    }

    if (!mounted) return;

    setState(() {
      searchingHospitals = true;
      loadingRoutes = true;
    });

    try {
      final hospitals =
          await _findNearbyHospitals();

      if (hospitals.isEmpty) {
        throw Exception(
          'No nearby hospitals found',
        );
      }

      double bestCombinedScore =
          double.infinity;

      Map<String, dynamic>?
          bestHospital;

      RouteOption? bestRoute;

      List<RouteOption>
          bestRoutes = [];

      for (final hospital
          in hospitals) {
        final hospitalRoutes =
            await RouteService
                .getRoutes(
          startLatitude:
              currentPosition!
                  .latitude,
          startLongitude:
              currentPosition!
                  .longitude,
          destinationLatitude:
              hospital['latitude'],
          destinationLongitude:
              hospital['longitude'],
        );

        if (hospitalRoutes
            .isEmpty) {
          continue;
        }

        double hospitalBestScore =
            double.infinity;

        RouteOption?
            hospitalBestRoute;

        for (final route
            in hospitalRoutes) {
          final risk =
              await _calculateRouteRisk(
            route,
          );

          final emergencyScore =
              risk.score * 2000 +
                  route.durationSeconds;

          if (emergencyScore <
              hospitalBestScore) {
            hospitalBestScore =
                emergencyScore;

            hospitalBestRoute =
                route;
          }
        }

        if (hospitalBestRoute ==
            null) {
          continue;
        }

        final hospitalDistance =
            hospital['distance']
                as double;

        final hospitalTime =
            hospitalBestRoute
                .durationSeconds;

        final combinedScore =
            hospitalBestScore +
                hospitalDistance *
                    0.05 +
                hospitalTime *
                    0.20;

        if (combinedScore <
            bestCombinedScore) {
          bestCombinedScore =
              combinedScore;

          bestHospital =
              hospital;

          bestRoute =
              hospitalBestRoute;

          bestRoutes =
              hospitalRoutes;
        }
      }

      if (bestHospital ==
              null ||
          bestRoute == null) {
        throw Exception(
          'Unable to find hospital route',
        );
      }

      destination =
          LatLng(
        bestHospital['latitude'],
        bestHospital['longitude'],
      );

      destinationAddress =
          bestHospital['name'];

      selectedHospitalName =
          bestHospital['name'];

      selectedHospitalAddress =
          bestHospital['address'];

      selectedHospitalDistance =
          bestHospital['distance'];

      routes = bestRoutes;

      routeSegments.clear();
      routeRiskLevels.clear();

      for (int i = 0;
          i < bestRoutes.length;
          i++) {
        final segments =
            _buildDemoSegments(
          bestRoutes[i],
          i,
          bestRoutes.length,
        );

        routeSegments[i] =
            segments;

        routeRiskLevels[i] =
            _riskFromDemoSegments(
          segments,
        );
      }

      int bestIndex =
          bestRoutes.indexOf(
        bestRoute,
      );

      if (bestIndex < 0) {
        bestIndex = 0;
      }

      selectedRouteIndex =
          bestIndex;

      await _loadRiskInformation(
        bestRoute,
      );

      final demoRisk =
          routeRiskLevels[
                  bestIndex] ??
              RiskLevel.safe;

      selectedRisk =
          _mergeRisk(
        selectedRisk,
        demoRisk,
      );

      if (!mounted) return;

      setState(() {
        loadingRoutes = false;
        searchingHospitals = false;
      });

      fitMapToRoute(
        bestRoute,
      );

      _showMessage(
        'Best hospital route selected',
      );
    } catch (e) {
      debugPrint(
        'Emergency route error: $e',
      );

      if (!mounted) return;

      setState(() {
        loadingRoutes = false;
        searchingHospitals = false;
      });

      _showMessage(
        'Unable to find hospital route',
      );
    }
  }

  // ==========================================================
  // VOICE
  // ==========================================================

  Future<void> _speakRouteSummary(
    RouteOption route,
    RiskLevel risk,
  ) async {
    if (!voiceEnabled) {
      return;
    }

    try {
      if (mounted) {
        setState(() {
          speaking = true;
        });
      }

      final text =
          'Route ${selectedRouteIndex + 1}. '
          '${_formatDistance(route.distanceMeters)}. '
          '${_formatDuration(route.durationSeconds)}. '
          'Risk level is '
          '${_riskText(risk)}.';

      await VoiceService.instance
          .speak(text);
    } catch (e) {
      debugPrint(
        'Voice error: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          speaking = false;
        });
      }
    }
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

    final remaining =
        minutes % 60;

    return '${hours}h ${remaining}m';
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
        return 'Impassable';
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
        return Colors.green;

      case RiskLevel.moderate:
        return Colors.orange;

      case RiskLevel.impassable:
        return Colors.red;
    }
  }

  // ==========================================================
  // CONDITION COLOR
  // ==========================================================

  Color _conditionColor(
    DemoRoadCondition condition,
  ) {
    switch (condition) {
      case DemoRoadCondition.dry:
        return Colors.green;

      case DemoRoadCondition.puddle:
        return Colors.orange;

      case DemoRoadCondition.flood:
        return Colors.red;
    }
  }

  // ==========================================================
  // CONDITION TEXT
  // ==========================================================

  String _conditionText(
    DemoRoadCondition condition,
  ) {
    switch (condition) {
      case DemoRoadCondition.dry:
        return 'Dry';

      case DemoRoadCondition.puddle:
        return 'Puddle';

      case DemoRoadCondition.flood:
        return 'Flood';
    }
  }

  // ==========================================================
  // MODE ICON
  // ==========================================================

  IconData _modeIcon() {
    if (isAmbulance) {
      return Icons.local_hospital;
    }

    if (isRescue) {
      return Icons.emergency;
    }

    return Icons.directions_car;
  }

  // ==========================================================
  // MODE TITLE
  // ==========================================================

  String _modeTitle() {
    if (isAmbulance) {
      return 'Ambulance Route';
    }

    if (isRescue) {
      return 'Rescue Route';
    }

    return 'Safe Travel';
  }

  // ==========================================================
  // MESSAGE
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
        ),
      );
  }

  // ==========================================================
  // RISK LEGEND
  // ==========================================================

  Widget _buildRiskLegend() {
    return Card(
      elevation: 5,
      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(
          14,
        ),
      ),
      child: Padding(
        padding:
            const EdgeInsets
                .symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Road Condition',
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
                fontSize: 13,
              ),
            ),

            const SizedBox(
              height: 7,
            ),

            _legendItem(
              Colors.green,
              'Dry • Safe',
            ),

            const SizedBox(
              height: 5,
            ),

            _legendItem(
              Colors.orange,
              'Puddle • Moderate',
            ),

            const SizedBox(
              height: 5,
            ),

            _legendItem(
              Colors.red,
              'Flood • Impassable',
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(
    Color color,
    String text,
  ) {
    return Row(
      mainAxisSize:
          MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration:
              BoxDecoration(
            color: color,
            shape:
                BoxShape.circle,
          ),
        ),
        const SizedBox(
          width: 7,
        ),
        Text(
          text,
          style:
              const TextStyle(
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // OLD ROUTE CARD
  // ==========================================================

  Widget _buildRouteCard(
    int index,
    RouteOption route,
  ) {
    final selected =
        index ==
            selectedRouteIndex;

    final risk =
        routeRiskLevels[index] ??
            RiskLevel.safe;

    final segments =
        routeSegments[index] ??
            [];

    final floodCount =
        segments
            .where(
              (s) =>
                  s.condition ==
                  DemoRoadCondition
                      .flood,
            )
            .length;

    final puddleCount =
        segments
            .where(
              (s) =>
                  s.condition ==
                  DemoRoadCondition
                      .puddle,
            )
            .length;

    return GestureDetector(
      onTap: () =>
          _selectRoute(index),
      child:
          AnimatedContainer(
        duration:
            const Duration(
          milliseconds: 200,
        ),
        width: 220,
        margin:
            const EdgeInsets.only(
          right: 12,
        ),
        padding:
            const EdgeInsets.all(
          14,
        ),
        decoration:
            BoxDecoration(
          color: selected
              ? primaryColor
              : Colors.white,
          borderRadius:
              BorderRadius.circular(
            18,
          ),
          border: Border.all(
            color: selected
                ? primaryColor
                : Colors.grey.shade300,
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 8,
              color: Colors.black
                  .withOpacity(
                0.08,
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment
                  .start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons
                          .check_circle
                      : Icons.route,
                  color: selected
                      ? Colors.white
                      : primaryColor,
                  size: 20,
                ),

                const SizedBox(
                  width: 8,
                ),

                Text(
                  'Route ${index + 1}',
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : Colors.black87,
                    fontWeight:
                        FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 10,
            ),

            Row(
              children: [
                Icon(
                  Icons.straighten,
                  size: 15,
                  color: selected
                      ? Colors.white70
                      : Colors.grey,
                ),

                const SizedBox(
                  width: 4,
                ),

                Text(
                  _formatDistance(
                    route.distanceMeters,
                  ),
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : Colors.black87,
                  ),
                ),

                const SizedBox(
                  width: 12,
                ),

                Icon(
                  Icons.access_time,
                  size: 15,
                  color: selected
                      ? Colors.white70
                      : Colors.grey,
                ),

                const SizedBox(
                  width: 4,
                ),

                Text(
                  _formatDuration(
                    route.durationSeconds,
                  ),
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : Colors.black87,
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 9,
            ),

            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration:
                      BoxDecoration(
                    color: selected
                        ? Colors.white
                            .withOpacity(
                            0.18,
                          )
                        : _riskColor(
                            risk,
                          ).withOpacity(
                            0.12,
                          ),
                    borderRadius:
                        BorderRadius
                            .circular(
                      8,
                    ),
                  ),
                  child: Text(
                    _riskText(risk),
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : _riskColor(
                              risk,
                            ),
                      fontSize: 11,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(
                  width: 6,
                ),

                if (puddleCount > 0)
                  Text(
                    '🟡 $puddleCount',
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : Colors.orange,
                      fontSize: 11,
                    ),
                  ),

                const SizedBox(
                  width: 5,
                ),

                if (floodCount > 0)
                  Text(
                    '🔴 $floodCount',
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : Colors.red,
                      fontSize: 11,
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
  // BUILD
  // ==========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      body: Stack(
        children: [
          // ====================================================
          // MAP
          // ====================================================

          FlutterMap(
            mapController:
                mapController,

            options: MapOptions(
              initialCenter:
                  const LatLng(
                13.0827,
                80.2707,
              ),
              initialZoom: 13,
              onTap: _onMapTap,
            ),

            children: [
              // ==================================================
              // OPENSTREETMAP
              // ==================================================

              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/'
                    '{z}/{x}/{y}.png',

                userAgentPackageName:
                    'com.example.hydropulse',
              ),

              // ==================================================
              // AI ROUTES
              // ==================================================

              if (aiRoutes.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (
                      int i = 0;
                      i < aiRoutes.length;
                      i++
                    )
                      Polyline(
                        points:
                            aiRoutes[i]
                                .points,

                        strokeWidth:
                            i ==
                                    aiSelectedRouteIndex
                                ? 9
                                : 5,

                        color:
                            _aiRouteColor(
                          aiRoutes[i],
                        ).withOpacity(
                          i ==
                                  aiSelectedRouteIndex
                              ? 1.0
                              : 0.72,
                        ),

                        borderStrokeWidth:
                            i ==
                                    aiSelectedRouteIndex
                                ? 2
                                : 0,

                        borderColor:
                            Colors.black
                                .withOpacity(
                          0.12,
                        ),
                      ),
                  ],
                ),

              // ==================================================
              // OLD ROUTES
              // ==================================================

              if (routes.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (
                      int routeIndex = 0;
                      routeIndex <
                          routes.length;
                      routeIndex++
                    )
                      if (routeSegments
                          .containsKey(
                        routeIndex,
                      ))
                        for (
                          final segment
                              in routeSegments[
                                  routeIndex]!
                        )
                          Polyline(
                            points: [
                              segment
                                  .start,
                              segment
                                  .end,
                            ],
                            strokeWidth:
                                routeIndex ==
                                        selectedRouteIndex
                                    ? 7
                                    : 4,
                            color:
                                _conditionColor(
                              segment
                                  .condition,
                            ).withOpacity(
                              routeIndex ==
                                      selectedRouteIndex
                                  ? 1.0
                                  : 0.70,
                            ),
                          )
                      else
                        Polyline(
                          points:
                              _routePoints(
                            routes[
                                routeIndex],
                          ),
                          strokeWidth:
                              routeIndex ==
                                      selectedRouteIndex
                                  ? 7
                                  : 4,
                          color:
                              routeIndex ==
                                      selectedRouteIndex
                                  ? primaryColor
                                  : Colors.grey,
                        ),
                  ],
                ),

              // ==================================================
              // MARKERS
              // ==================================================

              MarkerLayer(
                markers: [
                  if (currentPosition !=
                      null)
                    Marker(
                      point: LatLng(
                        currentPosition!
                            .latitude,
                        currentPosition!
                            .longitude,
                      ),
                      width: 45,
                      height: 45,
                      child:
                          Container(
                        decoration:
                            BoxDecoration(
                          color: Colors.blue
                              .withOpacity(
                            0.18,
                          ),
                          shape:
                              BoxShape.circle,
                        ),
                        child:
                            const Icon(
                          Icons
                              .my_location,
                          color:
                              Colors.blue,
                          size: 28,
                        ),
                      ),
                    ),

                  if (destination !=
                      null)
                    Marker(
                      point:
                          destination!,
                      width: 50,
                      height: 50,
                      child:
                          Container(
                        decoration:
                            BoxDecoration(
                          color: Colors.red
                              .withOpacity(
                            0.15,
                          ),
                          shape:
                              BoxShape.circle,
                        ),
                        child:
                            const Icon(
                          Icons
                              .location_on,
                          color:
                              Colors.red,
                          size: 38,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // ====================================================
          // SEARCH BAR
          // ====================================================

          Positioned(
            top: 10,
            left: 14,
            right: 14,
            child: Material(
              elevation: 6,
              borderRadius:
                  BorderRadius.circular(
                16,
              ),
              child: TextField(
                controller:
                    _searchController,

                textInputAction:
                    TextInputAction
                        .search,

                onSubmitted: (_) =>
                    _searchDestination(),

                decoration:
                    InputDecoration(
                  hintText:
                      'Search destination...',

                  prefixIcon:
                      const Icon(
                    Icons.search,
                  ),

                  suffixIcon:
                      IconButton(
                    icon:
                        const Icon(
                      Icons.clear,
                    ),
                    onPressed: () {
                      _searchController
                          .clear();
                    },
                  ),

                  filled: true,
                  fillColor:
                      Colors.white,

                  border:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius
                            .circular(
                      16,
                    ),
                    borderSide:
                        BorderSide.none,
                  ),

                  contentPadding:
                      const EdgeInsets
                          .symmetric(
                    vertical: 15,
                    horizontal: 12,
                  ),
                ),
              ),
            ),
          ),

          // ====================================================
          // TOP CARD
          // ====================================================

          Positioned(
            top: 72,
            left: 14,
            right: 14,
            child: Card(
              elevation: 6,
              shape:
                  RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(
                  18,
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  15,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration:
                          BoxDecoration(
                        color: primaryColor
                            .withOpacity(
                          0.1,
                        ),
                        shape:
                            BoxShape.circle,
                      ),
                      child: Icon(
                        _modeIcon(),
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
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            _modeTitle(),
                            style:
                                const TextStyle(
                              fontSize: 18,
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),

                          const SizedBox(
                            height: 3,
                          ),

                          Text(
                            destinationAddress ??
                                'Search or tap the map to choose destination',
                            maxLines: 2,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                TextStyle(
                              color: Colors
                                  .grey
                                  .shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ====================================================
          // RISK LEGEND
          // ====================================================

          if (routes.isNotEmpty ||
              aiRoutes.isNotEmpty)
            Positioned(
              top: 182,
              right: 14,
              child:
                  _buildRiskLegend(),
            ),

          // ====================================================
          // LOADING
          // ====================================================

          if (loadingRoutes)
            const Center(
              child: Card(
                elevation: 6,
                child: Padding(
                  padding:
                      EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(
                        height: 12,
                      ),
                      Text(
                        'Finding safe road routes...',
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ====================================================
          // LOCATION BUTTON
          // ====================================================

          Positioned(
            right: 16,
            bottom:
                (routes.isNotEmpty ||
                        aiRoutes.isNotEmpty)
                    ? 300
                    : 120,
            child:
                FloatingActionButton(
              heroTag:
                  'locationButton',
              mini: true,
              onPressed:
                  loadingLocation
                      ? null
                      : _getCurrentLocation,
              child:
                  const Icon(
                Icons.my_location,
              ),
            ),
          ),

          // ====================================================
          // VOICE BUTTON
          // ====================================================

          Positioned(
            right: 16,
            bottom:
                (routes.isNotEmpty ||
                        aiRoutes.isNotEmpty)
                    ? 245
                    : 175,
            child:
                FloatingActionButton(
              heroTag:
                  'voiceButton',
              mini: true,
              onPressed: () async {
                setState(() {
                  voiceEnabled =
                      !voiceEnabled;
                });

                if (voiceEnabled &&
                    aiRoutes
                        .isNotEmpty) {
                  await _speakAiRouteSummary(
                    aiRoutes[
                        aiSelectedRouteIndex],
                  );
                } else if (
                    voiceEnabled &&
                    routes.isNotEmpty) {
                  await _speakRouteSummary(
                    routes[
                        selectedRouteIndex],
                    selectedRisk,
                  );
                }
              },
              child: Icon(
                voiceEnabled
                    ? Icons.volume_up
                    : Icons.volume_off,
              ),
            ),
          ),

          // ====================================================
          // BOTTOM PANEL
          // ====================================================

          if (destination != null ||
              aiRoutes.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets
                        .fromLTRB(
                  16,
                  16,
                  16,
                  20,
                ),
                decoration:
                    const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(
                    top: Radius.circular(
                      28,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 15,
                      color:
                          Colors.black26,
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      // ==================================================
                      // DESTINATION
                      // ==================================================

                      Row(
                        children: [
                          const Icon(
                            Icons
                                .location_on,
                            color:
                                Colors.red,
                          ),

                          const SizedBox(
                            width: 8,
                          ),

                          Expanded(
                            child: Text(
                              destinationAddress ??
                                  'Destination',
                              maxLines: 2,
                              overflow:
                                  TextOverflow
                                      .ellipsis,
                              style:
                                  const TextStyle(
                                fontWeight:
                                    FontWeight
                                        .bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      // ==================================================
                      // AI ROUTES
                      // ==================================================

                      if (aiRoutes
                          .isNotEmpty)
                        SizedBox(
                          height: 158,
                          child:
                              ListView.builder(
                            scrollDirection:
                                Axis.horizontal,
                            itemCount:
                                aiRoutes
                                    .length,
                            itemBuilder:
                                (
                              context,
                              index,
                            ) {
                              return _buildAiRouteCard(
                                index,
                                aiRoutes[
                                    index],
                              );
                            },
                          ),
                        ),

                      // ==================================================
                      // OLD ROUTES
                      // ==================================================

                      if (routes
                          .isNotEmpty)
                        SizedBox(
                          height: 145,
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
                                index,
                                routes[
                                    index],
                              );
                            },
                          ),
                        ),

                      if (routes.isNotEmpty ||
                          aiRoutes.isNotEmpty)
                        const SizedBox(
                          height: 12,
                        ),

                      // ==================================================
                      // AI SELECTED RISK
                      // ==================================================

                      if (aiRoutes
                          .isNotEmpty)
                        Container(
                          width:
                              double.infinity,
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration:
                              BoxDecoration(
                            color:
                                _riskColor(
                              selectedRisk,
                            ).withOpacity(
                              0.10,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              12,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selectedRisk ==
                                        RiskLevel
                                            .safe
                                    ? Icons
                                        .check_circle
                                    : selectedRisk ==
                                            RiskLevel
                                                .moderate
                                        ? Icons
                                            .warning
                                        : Icons
                                            .dangerous,
                                color:
                                    _riskColor(
                                  selectedRisk,
                                ),
                              ),

                              const SizedBox(
                                width: 8,
                              ),

                              Expanded(
                                child:
                                    Text(
                                  'AI Selected Route: '
                                  '${_riskText(selectedRisk)}',
                                  style:
                                      TextStyle(
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                    color:
                                        _riskColor(
                                      selectedRisk,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // ==================================================
                      // OLD SELECTED RISK
                      // ==================================================

                      if (routes
                          .isNotEmpty)
                        Container(
                          width:
                              double.infinity,
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration:
                              BoxDecoration(
                            color:
                                _riskColor(
                              selectedRisk,
                            ).withOpacity(
                              0.10,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              12,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selectedRisk ==
                                        RiskLevel
                                            .safe
                                    ? Icons
                                        .check_circle
                                    : selectedRisk ==
                                            RiskLevel
                                                .moderate
                                        ? Icons
                                            .warning
                                        : Icons
                                            .dangerous,
                                color:
                                    _riskColor(
                                  selectedRisk,
                                ),
                              ),

                              const SizedBox(
                                width: 8,
                              ),

                              Expanded(
                                child:
                                    Text(
                                  'Selected Route: '
                                  '${_riskText(selectedRisk)}',
                                  style:
                                      TextStyle(
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                    color:
                                        _riskColor(
                                      selectedRisk,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(
                        height: 12,
                      ),

                      // ==================================================
                      // FIND ROUTE BUTTON
                      // ==================================================

                      SizedBox(
                        width:
                            double.infinity,
                        height: 52,
                        child:
                            ElevatedButton
                                .icon(
                          onPressed:
                              loadingRoutes
                                  ? null
                                  : _findSafestRoute,

                          icon:
                              const Icon(
                            Icons.route,
                          ),

                          label: Text(
                            aiRoutes.isNotEmpty ||
                                    routes.isNotEmpty
                                ? 'Recalculate Safest Route'
                                : 'Find Safest Route',
                          ),

                          style:
                              ElevatedButton
                                  .styleFrom(
                            backgroundColor:
                                primaryColor,
                            foregroundColor:
                                Colors.white,
                            shape:
                                RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// ROUTE RISK RESULT
// ============================================================

class _RouteRiskResult {
  final int score;
  final double rainfall;
  final double elevation;
  final double drainageDistance;
  final RiskLevel risk;

  double get drainingDistance =>
      drainageDistance;

  const _RouteRiskResult({
    required this.score,
    required this.rainfall,
    required this.elevation,
    required this.drainageDistance,
    required this.risk,
  });
}