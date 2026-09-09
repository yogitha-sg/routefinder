
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../services/weather_service.dart';
import '../services/route_service.dart';
import '../services/location_service.dart';
import '../services/elevation_service.dart';
import '../models/road_segment.dart';

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

class _MapScreenState extends State<MapScreen> {
  final MapController mapController = MapController();

  // ============================================================
  // LOCATION
  // ============================================================

  Position? currentPosition;
  LatLng? destination;

  bool isLoadingLocation = false;
  String locationError = '';

  // ============================================================
  // WEATHER
  // ============================================================

  // General/current rainfall shown before route analysis.
  double rainfall = 0;

  bool isLoadingWeather = true;

  // Rainfall for every route.
  //
  // routeRainfallScores[index] =
  // rainfall detected along that route.
  List<double> routeRainfallScores = [];

  // ============================================================
  // ROUTING
  // ============================================================

  List<RouteOption> routes = [];

  RouteOption? safestRoute;

  int selectedRouteIndex = 0;

  bool isLoadingRoutes = false;

  bool routeCalculated = false;

  String routeError = '';

  // ============================================================
  // RISK SCORES
  // ============================================================

  // Final risk score for every route.
  List<double> riskScores = [];

  // Elevation component for every route.
  List<double> elevationScores = [];

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    fetchWeather();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      getCurrentLocation();
    });
  }

  // ============================================================
  // WEATHER
  // ============================================================

  Future<void> fetchWeather() async {
    try {
      final rain = await WeatherService.getCurrentRainfall(
        latitude: 13.0827,
        longitude: 80.2707,
      );

      if (!mounted) return;

      setState(() {
        rainfall = rain;
        isLoadingWeather = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoadingWeather = false;
        rainfall = 0;
      });

      print('Weather loading failed: $e');
    }
  }

  // ============================================================
  // LOCATION
  // ============================================================

  Future<void> getCurrentLocation() async {
    if (isLoadingLocation) return;

    setState(() {
      isLoadingLocation = true;
      locationError = '';
    });

    try {
      final position = await LocationService.getCurrentLocation();

      if (!mounted) return;

      setState(() {
        currentPosition = position;
        isLoadingLocation = false;
      });

      final location = LatLng(
        position.latitude,
        position.longitude,
      );

      mapController.move(location, 14);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current location detected.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoadingLocation = false;
        locationError = e.toString().replaceFirst(
              'Exception: ',
              '',
            );
      });
    }
  }

  // ============================================================
  // DESTINATION
  // ============================================================

  void selectDestination(LatLng point) {
    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please detect your current location first.',
          ),
        ),
      );

      return;
    }

    setState(() {
      destination = point;

      routeCalculated = false;

      routes = [];

      safestRoute = null;

      riskScores = [];

      elevationScores = [];

      routeRainfallScores = [];

      routeError = '';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Destination selected. Tap "Find Safest Route".',
        ),
      ),
    );
  }

  // ============================================================
  // FIND REAL ROUTES + ANALYZE RISK
  // ============================================================

  Future<void> findSafestRoute() async {
    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please detect your current location first.',
          ),
        ),
      );

      return;
    }

    if (destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please tap on the map to select a destination.',
          ),
        ),
      );

      return;
    }

    setState(() {
      isLoadingRoutes = true;
      routeCalculated = false;
      routeError = '';
      routes = [];
      safestRoute = null;
      riskScores = [];
      elevationScores = [];
      routeRainfallScores = [];
    });

    try {
      // ========================================================
      // STEP 1
      // Get real road routes.
      // ========================================================

      final result = await RouteService.getRoutes(
        startLat: currentPosition!.latitude,
        startLng: currentPosition!.longitude,
        endLat: destination!.latitude,
        endLng: destination!.longitude,
      );

      if (!mounted) return;

      if (result.isEmpty) {
        throw Exception('No routes were found.');
      }

      setState(() {
        routes = result;
      });

      // ========================================================
      // STEP 2
      // Analyze every route.
      //
      // Each route gets:
      //
      // 1. Live rainfall along the route
      // 2. Real elevation
      // 3. Distance
      //
      // Then we calculate the final risk score.
      // ========================================================

      final safestIndex = await calculateSafestRouteIndex();

      if (!mounted) return;

      if (safestIndex >= routes.length) {
        selectedRouteIndex = 0;
      } else {
        selectedRouteIndex = safestIndex;
      }

      setState(() {
        safestRoute = routes[selectedRouteIndex];

        isLoadingRoutes = false;

        routeCalculated = true;
      });

      // ========================================================
      // STEP 3
      // Fit map to safest route.
      // ========================================================

      fitMapToRoute(routes[selectedRouteIndex]);

      // ========================================================
      // RESULT MESSAGE
      // ========================================================

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${routes.length} route${routes.length == 1 ? '' : 's'} analyzed using live rainfall, elevation and distance.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoadingRoutes = false;
        routeCalculated = false;

        routeError = e.toString().replaceFirst(
              'Exception: ',
              '',
            );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to find route: $routeError',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
  // ELEVATION RISK
  // ============================================================

  Future<double> calculateElevationRisk(
    RouteOption route,
  ) async {
    try {
      final elevations =
          await ElevationService.getElevations(
        route.coordinates,
      );

      if (elevations.isEmpty) {
        print(
          'Elevation data empty. Using fallback score.',
        );

        return 25.0;
      }

      final minElevation =
          elevations.reduce(
        (a, b) => a < b ? a : b,
      );

      final maxElevation =
          elevations.reduce(
        (a, b) => a > b ? a : b,
      );

      final averageElevation =
          elevations.reduce(
                (a, b) => a + b,
              ) /
              elevations.length;

      final elevationRange =
          maxElevation - minElevation;

      // ========================================================
      // LOWER TERRAIN COMPONENT
      // ========================================================

      double lowTerrainScore = 0;

      if (minElevation < 2) {
        lowTerrainScore = 30;
      } else if (minElevation < 5) {
        lowTerrainScore = 22;
      } else if (minElevation < 10) {
        lowTerrainScore = 14;
      } else if (minElevation < 20) {
        lowTerrainScore = 7;
      } else {
        lowTerrainScore = 3;
      }

      // ========================================================
      // TERRAIN VARIATION
      // ========================================================

      final terrainVariationScore =
          elevationRange.clamp(0, 10).toDouble();

      final score =
          lowTerrainScore +
          terrainVariationScore;

      print(
        'Elevation analysis: '
        'min=${minElevation.toStringAsFixed(2)}m, '
        'avg=${averageElevation.toStringAsFixed(2)}m, '
        'max=${maxElevation.toStringAsFixed(2)}m, '
        'score=${score.toStringAsFixed(1)}',
      );

      return score.clamp(0, 40).toDouble();
    } catch (e) {
      print(
        'Elevation analysis failed: $e',
      );

      // Keep routing working if elevation API fails.
      return 20.0;
    }
  }

  // ============================================================
  // RAINFALL SCORE
  // ============================================================

  double calculateRainfallRiskScore(
    double routeRainfall,
  ) {
    if (routeRainfall >= 100) {
      return 50;
    }

    if (routeRainfall >= 75) {
      return 42;
    }

    if (routeRainfall >= 50) {
      return 35;
    }

    if (routeRainfall >= 20) {
      return 25;
    }

    if (routeRainfall > 0) {
      return 15;
    }

    return 5;
  }

  // ============================================================
  // ROUTE RAINFALL
  // ============================================================

  Future<double> calculateRouteRainfall(
    RouteOption route,
  ) async {
    try {
      final routeRainfall =
          await WeatherService.getRouteRainfall(
        route.coordinates,
      );

      print(
        'Route rainfall: '
        '${routeRainfall.toStringAsFixed(2)} mm',
      );

      return routeRainfall;
    } catch (e) {
      print(
        'Route rainfall calculation failed: $e',
      );

      // Keep routing working if weather API fails.
      return rainfall;
    }
  }

  // ============================================================
  // ROUTE RISK SCORE
  // ============================================================

  Future<double> calculateRouteRiskScore(
    RouteOption route,
    int routeIndex,
  ) async {
    // ==========================================================
    // LIVE RAINFALL ALONG THIS ROUTE
    // ==========================================================

    final routeRainfall =
        await calculateRouteRainfall(route);

    final rainfallScore =
        calculateRainfallRiskScore(
      routeRainfall,
    );

    // ==========================================================
    // REAL ELEVATION
    // ==========================================================

    final elevationRisk =
        await calculateElevationRisk(route);

    // ==========================================================
    // DISTANCE
    // ==========================================================

    final distanceScore =
        route.distanceKm * 1.2;

    // ==========================================================
    // FINAL SCORE
    // ==========================================================

    final score =
        rainfallScore +
        elevationRisk +
        distanceScore;

    print(
      'Route ${routeIndex + 1}: '
      'rainfall=${routeRainfall.toStringAsFixed(1)} mm, '
      'rainfallScore=${rainfallScore.toStringAsFixed(1)}, '
      'elevation=${elevationRisk.toStringAsFixed(1)}, '
      'distanceScore=${distanceScore.toStringAsFixed(1)}, '
      'TOTAL=${score.toStringAsFixed(1)}',
    );

    return score;
  }

  // ============================================================
  // CALCULATE SAFEST ROUTE
  // ============================================================

  Future<int> calculateSafestRouteIndex() async {
    if (routes.isEmpty) {
      return 0;
    }

    double lowestScore = double.infinity;

    int safestIndex = 0;

    final calculatedRiskScores = <double>[];

    final calculatedElevationScores = <double>[];

    final calculatedRainfallScores = <double>[];

    // ==========================================================
    // Analyze every route.
    // ==========================================================

    for (int i = 0; i < routes.length; i++) {
      final route = routes[i];

      // --------------------------------------------------------
      // LIVE RAINFALL ALONG THIS ROUTE
      // --------------------------------------------------------

      final routeRainfall =
          await calculateRouteRainfall(route);

      final rainfallScore =
          calculateRainfallRiskScore(
        routeRainfall,
      );

      // --------------------------------------------------------
      // REAL ELEVATION
      // --------------------------------------------------------

      final elevationRisk =
          await calculateElevationRisk(route);

      // --------------------------------------------------------
      // DISTANCE
      // --------------------------------------------------------

      final distanceScore =
          route.distanceKm * 1.2;

      // --------------------------------------------------------
      // FINAL RISK
      // --------------------------------------------------------

      final score =
          rainfallScore +
          elevationRisk +
          distanceScore;

      // --------------------------------------------------------
      // Save values.
      // --------------------------------------------------------

      calculatedRiskScores.add(score);

      calculatedElevationScores.add(
        elevationRisk,
      );

      calculatedRainfallScores.add(
        routeRainfall,
      );

      print(
        '================================================',
      );

      print(
        'ROUTE ${i + 1}',
      );

      print(
        'Rainfall: '
        '${routeRainfall.toStringAsFixed(2)} mm',
      );

      print(
        'Rainfall Risk: '
        '${rainfallScore.toStringAsFixed(1)}',
      );

      print(
        'Elevation Risk: '
        '${elevationRisk.toStringAsFixed(1)}',
      );

      print(
        'Distance Score: '
        '${distanceScore.toStringAsFixed(1)}',
      );

      print(
        'FINAL RISK SCORE: '
        '${score.toStringAsFixed(1)}',
      );

      print(
        '================================================',
      );

      if (score < lowestScore) {
        lowestScore = score;
        safestIndex = i;
      }
    }

    // ==========================================================
    // SAVE SCORES FOR UI
    // ==========================================================

    if (mounted) {
      setState(() {
        riskScores =
            calculatedRiskScores;

        elevationScores =
            calculatedElevationScores;

        routeRainfallScores =
            calculatedRainfallScores;

        // Show the safest route rainfall as the main rainfall.
        if (calculatedRainfallScores.isNotEmpty) {
          rainfall =
              calculatedRainfallScores[safestIndex];
        }
      });
    }

    print(
      'SAFEST ROUTE: Route ${safestIndex + 1}',
    );

    print(
      'LOWEST RISK: '
      '${lowestScore.toStringAsFixed(1)}',
    );

    return safestIndex;
  }

  // ============================================================
  // GET STORED RISK SCORE
  // ============================================================

  double getRouteRiskScore(
    int index,
  ) {
    if (index < 0 ||
        index >= riskScores.length) {
      return 0;
    }

    return riskScores[index];
  }

  // ============================================================
  // GET STORED ELEVATION SCORE
  // ============================================================

  double getElevationScore(
    int index,
  ) {
    if (index < 0 ||
        index >= elevationScores.length) {
      return 0;
    }

    return elevationScores[index];
  }

  // ============================================================
  // GET ROUTE RAINFALL
  // ============================================================

  double getRouteRainfall(
    int index,
  ) {
    if (index < 0 ||
        index >= routeRainfallScores.length) {
      return rainfall;
    }

    return routeRainfallScores[index];
  }

  // ============================================================
  // RISK LEVEL
  // ============================================================

  RiskLevel routeRiskLevel(
    int routeIndex,
  ) {
    final score =
        getRouteRiskScore(routeIndex);

    if (score >= 75) {
      return RiskLevel.impassable;
    }

    if (score >= 45) {
      return RiskLevel.moderate;
    }

    return RiskLevel.safe;
  }

  // ============================================================
  // RISK COLOR
  // ============================================================

  Color riskColor(
    RiskLevel level,
  ) {
    switch (level) {
      case RiskLevel.safe:
        return Colors.green;

      case RiskLevel.moderate:
        return Colors.orange;

      case RiskLevel.impassable:
        return Colors.red;
    }
  }

  // ============================================================
  // RISK TEXT
  // ============================================================

  String riskText(
    RiskLevel level,
  ) {
    switch (level) {
      case RiskLevel.safe:
        return 'SAFE';

      case RiskLevel.moderate:
        return 'MODERATE';

      case RiskLevel.impassable:
        return 'HIGH RISK';
    }
  }

  // ============================================================
  // RISK DESCRIPTION
  // ============================================================

  String riskDescription(
    RiskLevel level,
  ) {
    switch (level) {
      case RiskLevel.safe:
        return 'Lower calculated flood susceptibility';

      case RiskLevel.moderate:
        return 'Moderate calculated flood susceptibility';

      case RiskLevel.impassable:
        return 'Higher calculated flood susceptibility';
    }
  }

  // ============================================================
  // FIT MAP TO SELECTED ROUTE
  // ============================================================

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

    for (final point in route.coordinates) {
      final lat = point[0];
      final lng = point[1];

      if (lat < minLat) {
        minLat = lat;
      }

      if (lat > maxLat) {
        maxLat = lat;
      }

      if (lng < minLng) {
        minLng = lng;
      }

      if (lng > maxLng) {
        maxLng = lng;
      }
    }

    if (currentPosition != null) {
      minLat = minLat < currentPosition!.latitude
          ? minLat
          : currentPosition!.latitude;

      maxLat = maxLat > currentPosition!.latitude
          ? maxLat
          : currentPosition!.latitude;

      minLng = minLng < currentPosition!.longitude
          ? minLng
          : currentPosition!.longitude;

      maxLng = maxLng > currentPosition!.longitude
          ? maxLng
          : currentPosition!.longitude;
    }

    if (destination != null) {
      minLat = minLat < destination!.latitude
          ? minLat
          : destination!.latitude;

      maxLat = maxLat > destination!.latitude
          ? maxLat
          : destination!.latitude;

      minLng = minLng < destination!.longitude
          ? minLng
          : destination!.longitude;

      maxLng = maxLng > destination!.longitude
          ? maxLng
          : destination!.longitude;
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

  // ============================================================
  // CALCULATE ZOOM
  // ============================================================

  double calculateZoom() {
    if (currentPosition == null ||
        destination == null) {
      return 13;
    }

    final distance =
        const Distance().as(
      LengthUnit.Kilometer,
      LatLng(
        currentPosition!.latitude,
        currentPosition!.longitude,
      ),
      destination!,
    );

    if (distance < 2) {
      return 15;
    }

    if (distance < 5) {
      return 14;
    }

    if (distance < 10) {
      return 13;
    }

    if (distance < 20) {
      return 12;
    }

    return 11;
  }

  // ============================================================
  // SELECT ROUTE
  // ============================================================

  void selectRoute(
    int index,
  ) {
    if (index < 0 ||
        index >= routes.length) {
      return;
    }

    setState(() {
      selectedRouteIndex = index;

      safestRoute = routes[index];

      // Update the main displayed rainfall
      // when the user selects another route.
      rainfall = getRouteRainfall(index);
    });

    fitMapToRoute(
      routes[index],
    );
  }

  // ============================================================
  // TRANSPORT ICON
  // ============================================================

  IconData transportIcon() {
    final mode =
        widget.travelMode.toLowerCase();

    if (mode.contains('bike')) {
      return Icons.two_wheeler;
    }

    if (mode.contains('bus')) {
      return Icons.directions_bus;
    }

    if (mode.contains('walking')) {
      return Icons.directions_walk;
    }

    if (mode.contains('ambulance')) {
      return Icons.local_hospital;
    }

    if (mode.contains('rescue')) {
      return Icons.emergency;
    }

    return Icons.directions_car;
  }

  // ============================================================
  // FORMAT DISTANCE
  // ============================================================

  String formatDistance(
    double km,
  ) {
    if (km < 1) {
      return '${(km * 1000).round()} m';
    }

    return '${km.toStringAsFixed(1)} km';
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'HydroPulse Map',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),

      body: Stack(
        children: [
          // ======================================================
          // MAP
          // ======================================================

          FlutterMap(
            mapController: mapController,

            options: MapOptions(
              initialCenter: const LatLng(
                13.0827,
                80.2707,
              ),

              initialZoom: 11.5,

              onTap: (
                tapPosition,
                point,
              ) {
                if (widget.selectionMode) {
                  selectDestination(point);
                }
              },
            ),

            children: [
              // ==================================================
              // OPEN STREET MAP
              // ==================================================

              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',

                userAgentPackageName:
                    'com.example.hydropulse',
              ),

              // ==================================================
              // REAL ROAD ROUTES
              // ==================================================

              if (routes.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (
                      int i = 0;
                      i < routes.length;
                      i++
                    )
                      Polyline(
                        points: routes[i]
                            .coordinates
                            .map(
                              (point) => LatLng(
                                point[0],
                                point[1],
                              ),
                            )
                            .toList(),

                        strokeWidth:
                            i == selectedRouteIndex
                                ? 9
                                : 5,

                        color:
                            riskScores.length ==
                                    routes.length
                                ? riskColor(
                                    routeRiskLevel(i),
                                  )
                                : Colors.blue,
                      ),
                  ],
                ),

              // ==================================================
              // MARKERS
              // ==================================================

              MarkerLayer(
                markers: [
                  // CURRENT LOCATION

                  if (currentPosition != null)
                    Marker(
                      point: LatLng(
                        currentPosition!.latitude,
                        currentPosition!.longitude,
                      ),

                      width: 55,
                      height: 55,

                      child: Container(
                        decoration:
                            BoxDecoration(
                          color: Colors.blue
                              .withOpacity(0.15),

                          shape: BoxShape.circle,
                        ),

                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                          size: 35,
                        ),
                      ),
                    ),

                  // DESTINATION

                  if (destination != null)
                    Marker(
                      point: destination!,

                      width: 55,
                      height: 55,

                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 42,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // ======================================================
          // TRANSPORT CARD
          // ======================================================

          Positioned(
            top: 12,
            left: 12,
            right: 12,

            child: Card(
              elevation: 7,

              child: Padding(
                padding:
                    const EdgeInsets.all(13),

                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          Colors.blue
                              .withOpacity(0.12),

                      child: Icon(
                        transportIcon(),
                        color: Colors.blue,
                      ),
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,

                        children: [
                          const Text(
                            'Transport Mode',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),

                          Text(
                            widget.travelMode,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.bold,
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

          // ======================================================
          // LOCATION / DESTINATION INSTRUCTIONS
          // ======================================================

          if (widget.selectionMode &&
              !routeCalculated)
            Positioned(
              top: 90,
              left: 12,
              right: 12,

              child: Card(
                elevation: 6,

                child: Padding(
                  padding:
                      const EdgeInsets.all(13),

                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [
                      const Text(
                        'Select your locations',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(
                        height: 7,
                      ),

                      Row(
                        children: [
                          const Icon(
                            Icons.my_location,
                            color: Colors.blue,
                            size: 18,
                          ),

                          const SizedBox(
                            width: 6,
                          ),

                          Expanded(
                            child: Text(
                              currentPosition ==
                                      null
                                  ? 'Current location: Detecting...'
                                  : 'Current location: Detected',

                              style:
                                  const TextStyle(
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 5,
                      ),

                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 18,
                          ),

                          const SizedBox(
                            width: 6,
                          ),

                          Expanded(
                            child: Text(
                              destination ==
                                      null
                                  ? 'Tap anywhere on the map to choose destination'
                                  : 'Destination selected',

                              style:
                                  const TextStyle(
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ======================================================
          // LOADING ROUTES
          // ======================================================

          if (isLoadingRoutes)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color:
                      Colors.black.withOpacity(
                    0.18,
                  ),

                  child: Center(
                    child: Card(
                      elevation: 8,

                      child: Padding(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 25,
                          vertical: 20,
                        ),

                        child: Column(
                          mainAxisSize:
                              MainAxisSize.min,

                          children: const [
                            CircularProgressIndicator(),

                            SizedBox(
                              height: 15,
                            ),

                            Text(
                              'Analyzing safest routes...',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),

                            SizedBox(
                              height: 5,
                            ),

                            Text(
                              'Checking live rainfall, elevation and distance',
                              style: TextStyle(
                                color:
                                    Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ======================================================
          // MY LOCATION BUTTON
          // ======================================================

          Positioned(
            right: 16,

            bottom:
                widget.selectionMode &&
                        !routeCalculated
                    ? 150
                    : 350,

            child: FloatingActionButton(
              heroTag:
                  'hydropulse_my_location',

              backgroundColor:
                  Colors.white,

              foregroundColor:
                  Colors.blue,

              onPressed:
                  isLoadingLocation
                      ? null
                      : getCurrentLocation,

              child:
                  isLoadingLocation
                      ? const SizedBox(
                          width: 23,
                          height: 23,

                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Icon(
                          Icons.my_location,
                        ),
            ),
          ),

          // ======================================================
          // FIND SAFEST ROUTE BUTTON
          // ======================================================

          if (widget.selectionMode &&
              !routeCalculated &&
              !isLoadingRoutes)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,

              child: SizedBox(
                height: 55,

                child: ElevatedButton.icon(
                  onPressed:
                      findSafestRoute,

                  icon: const Icon(
                    Icons.route,
                  ),

                  label: const Text(
                    'Find Safest Route',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

          // ======================================================
          // RESULT CARD
          // ======================================================

          if (routeCalculated &&
              safestRoute != null)
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,

              child: Card(
                elevation: 10,

                child: Padding(
                  padding:
                      const EdgeInsets.all(14),

                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [
                      // ------------------------------------------
                      // HEADER
                      // ------------------------------------------

                      Row(
                        children: [
                          Container(
                            width: 45,
                            height: 45,

                            decoration:
                                BoxDecoration(
                              color:
                                  riskColor(
                                routeRiskLevel(
                                  selectedRouteIndex,
                                ),
                              ).withOpacity(
                                0.12,
                              ),

                              shape:
                                  BoxShape.circle,
                            ),

                            child: Icon(
                              Icons.shield,
                              color:
                                  riskColor(
                                routeRiskLevel(
                                  selectedRouteIndex,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(
                            width: 10,
                          ),

                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,

                              children: [
                                const Text(
                                  'Safest Route Found',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                  ),
                                ),

                                const SizedBox(
                                  height: 2,
                                ),

                                Text(
                                  'Lowest calculated risk among ${routes.length} route${routes.length == 1 ? '' : 's'}',

                                  style:
                                      const TextStyle(
                                    color:
                                        Colors.grey,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 10,
                      ),

                      // ------------------------------------------
                      // ROUTE + RISK
                      // ------------------------------------------

                      Row(
                        children: [
                          Text(
                            'Route ${selectedRouteIndex + 1}',

                            style:
                                const TextStyle(
                              fontSize: 19,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),

                          const SizedBox(
                            width: 10,
                          ),

                          Builder(
                            builder:
                                (context) {
                              final risk =
                                  routeRiskLevel(
                                selectedRouteIndex,
                              );

                              return Container(
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),

                                decoration:
                                    BoxDecoration(
                                  color:
                                      riskColor(
                                    risk,
                                  ).withOpacity(
                                    0.12,
                                  ),

                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                    20,
                                  ),
                                ),

                                child: Text(
                                  riskText(
                                    risk,
                                  ),

                                  style:
                                      TextStyle(
                                    color:
                                        riskColor(
                                      risk,
                                    ),

                                    fontWeight:
                                        FontWeight
                                            .bold,

                                    fontSize:
                                        11,
                                  ),
                                ),
                              );
                            },
                          ),

                          const Spacer(),

                          Text(
                            widget.travelMode,

                            style:
                                const TextStyle(
                              color:
                                  Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 7,
                      ),

                      // ------------------------------------------
                      // RISK DESCRIPTION
                      // ------------------------------------------

                      Builder(
                        builder:
                            (context) {
                          final risk =
                              routeRiskLevel(
                            selectedRouteIndex,
                          );

                          return Text(
                            riskDescription(
                              risk,
                            ),

                            style:
                                TextStyle(
                              color:
                                  riskColor(
                                risk,
                              ),

                              fontSize: 12,

                              fontWeight:
                                  FontWeight
                                      .w600,
                            ),
                          );
                        },
                      ),

                      const Divider(
                        height: 20,
                      ),

                      // ------------------------------------------
                      // INFORMATION
                      // ------------------------------------------

                      Row(
                        children: [
                          Expanded(
                            child:
                                _RiskInfo(
                              icon:
                                  Icons.route,
                              title:
                                  'Distance',
                              value:
                                  formatDistance(
                                safestRoute!
                                    .distanceKm,
                              ),
                            ),
                          ),

                          Expanded(
                            child:
                                _RiskInfo(
                              icon:
                                  Icons.access_time,
                              title:
                                  'ETA',
                              value:
                                  '${safestRoute!.durationMinutes} min',
                            ),
                          ),

                          Expanded(
                            child:
                                _RiskInfo(
                              icon:
                                  Icons.water_drop,
                              title:
                                  'Rainfall',
                              value:
                                  '${getRouteRainfall(selectedRouteIndex).toStringAsFixed(1)} mm',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 10,
                      ),

                      // ------------------------------------------
                      // RISK SCORE + ELEVATION
                      // ------------------------------------------

                      Container(
                        padding:
                            const EdgeInsets
                                .all(10),

                        decoration:
                            BoxDecoration(
                          color: Colors.grey
                              .withOpacity(
                            0.07,
                          ),

                          borderRadius:
                              BorderRadius
                                  .circular(
                            10,
                          ),

                          border: Border.all(
                            color: Colors
                                .grey.shade300,
                          ),
                        ),

                        child: Row(
                          children: [
                            Expanded(
                              child:
                                  _RiskInfo(
                                icon:
                                    Icons.analytics,
                                title:
                                    'Risk Score',
                                value:
                                    getRouteRiskScore(
                                  selectedRouteIndex,
                                ).toStringAsFixed(
                                  1,
                                ),
                              ),
                            ),

                            Expanded(
                              child:
                                  _RiskInfo(
                                icon:
                                    Icons.terrain,
                                title:
                                    'Elevation Risk',
                                value:
                                    '${getElevationScore(selectedRouteIndex).toStringAsFixed(1)} / 40',
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(
                        height: 5,
                      ),

                      const Text(
                        'Rainfall is sampled along the route. Elevation is one risk component and does not by itself confirm flooding or waterlogging.',

                        style:
                            TextStyle(
                          color:
                              Colors.grey,
                          fontSize: 9,
                        ),
                      ),

                      // ------------------------------------------
                      // AVAILABLE ROUTES
                      // ------------------------------------------

                      if (routes.length > 1)
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,

                          children: [
                            const SizedBox(
                              height: 12,
                            ),

                            const Text(
                              'Alternative Routes',

                              style:
                                  TextStyle(
                                fontWeight:
                                    FontWeight
                                        .bold,
                                fontSize: 13,
                              ),
                            ),

                            const SizedBox(
                              height: 7,
                            ),

                            SizedBox(
                              height: 78,

                              child:
                                  ListView
                                      .separated(
                                scrollDirection:
                                    Axis
                                        .horizontal,

                                itemCount:
                                    routes
                                        .length,

                                separatorBuilder:
                                    (
                                  _,
                                  __,
                                ) =>
                                        const SizedBox(
                                  width: 7,
                                ),

                                itemBuilder:
                                    (
                                  context,
                                  index,
                                ) {
                                  final route =
                                      routes[
                                          index];

                                  final risk =
                                      routeRiskLevel(
                                    index,
                                  );

                                  final score =
                                      getRouteRiskScore(
                                    index,
                                  );

                                  final routeRain =
                                      getRouteRainfall(
                                    index,
                                  );

                                  final selected =
                                      index ==
                                          selectedRouteIndex;

                                  return GestureDetector(
                                    onTap:
                                        () =>
                                            selectRoute(
                                      index,
                                    ),

                                    child:
                                        Container(
                                      width:
                                          165,

                                      padding:
                                          const EdgeInsets
                                              .all(
                                        8,
                                      ),

                                      decoration:
                                          BoxDecoration(
                                        color:
                                            selected
                                                ? riskColor(
                                                    risk,
                                                  ).withOpacity(
                                                    0.10,
                                                  )
                                                : Colors
                                                    .grey
                                                    .withOpacity(
                                                    0.06,
                                                  ),

                                        borderRadius:
                                            BorderRadius
                                                .circular(
                                          12,
                                        ),

                                        border:
                                            Border.all(
                                          color:
                                              selected
                                                  ? riskColor(
                                                      risk,
                                                    )
                                                  : Colors
                                                      .grey
                                                      .shade300,

                                          width:
                                              selected
                                                  ? 1.5
                                                  : 1,
                                        ),
                                      ),

                                      child:
                                          Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,

                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                selected
                                                    ? Icons
                                                        .radio_button_checked
                                                    : Icons
                                                        .radio_button_off,

                                                color:
                                                    selected
                                                        ? riskColor(
                                                            risk,
                                                          )
                                                        : Colors
                                                            .grey,

                                                size:
                                                    16,
                                              ),

                                              const SizedBox(
                                                width:
                                                    4,
                                              ),

                                              Text(
                                                'Route ${index + 1}',

                                                style:
                                                    const TextStyle(
                                                  fontWeight:
                                                      FontWeight
                                                          .bold,
                                                  fontSize:
                                                      12,
                                                ),
                                              ),

                                              const Spacer(),

                                              Icon(
                                                Icons
                                                    .shield,

                                                size:
                                                    15,

                                                color:
                                                    riskColor(
                                                  risk,
                                                ),
                                              ),
                                            ],
                                          ),

                                          const SizedBox(
                                            height:
                                                4,
                                          ),

                                          Row(
                                            children: [
                                              Text(
                                                formatDistance(
                                                  route
                                                      .distanceKm,
                                                ),

                                                style:
                                                    const TextStyle(
                                                  fontSize:
                                                      10,
                                                ),
                                              ),

                                              const SizedBox(
                                                width:
                                                    6,
                                              ),

                                              Text(
                                                '${route.durationMinutes} min',

                                                style:
                                                    const TextStyle(
                                                  fontSize:
                                                      10,
                                                  color:
                                                      Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),

                                          const SizedBox(
                                            height:
                                                3,
                                          ),

                                          Row(
                                            children: [
                                              Icon(
                                                Icons
                                                    .water_drop,
                                                size:
                                                    11,
                                                color:
                                                    Colors.blue,
                                              ),

                                              const SizedBox(
                                                width:
                                                    2,
                                              ),

                                              Text(
                                                '${routeRain.toStringAsFixed(1)} mm',

                                                style:
                                                    const TextStyle(
                                                  fontSize:
                                                      9,
                                                  color:
                                                      Colors.blue,
                                                ),
                                              ),

                                              const SizedBox(
                                                width:
                                                    5,
                                              ),

                                              Text(
                                                riskText(
                                                  risk,
                                                ),

                                                style:
                                                    TextStyle(
                                                  color:
                                                      riskColor(
                                                    risk,
                                                  ),

                                                  fontWeight:
                                                      FontWeight
                                                          .bold,

                                                  fontSize:
                                                      9,
                                                ),
                                              ),

                                              const Spacer(),

                                              Text(
                                                'Score ${score.toStringAsFixed(0)}',

                                                style:
                                                    const TextStyle(
                                                  fontSize:
                                                      9,

                                                  color:
                                                      Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),

          // ======================================================
          // LOCATION ERROR
          // ======================================================

          if (locationError.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: 90,

              child: Card(
                color:
                    Colors.red.shade50,

                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    10,
                  ),

                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_off,
                        color: Colors.red,
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      Expanded(
                        child: Text(
                          locationError,

                          style:
                              const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ======================================================
          // ROUTE ERROR
          // ======================================================

          if (routeError.isNotEmpty &&
              !isLoadingRoutes)
            Positioned(
              left: 12,
              right: 12,
              bottom: 90,

              child: Card(
                color:
                    Colors.red.shade50,

                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    10,
                  ),

                  child: Row(
                    children: [
                      const Icon(
                        Icons.wrong_location,
                        color: Colors.red,
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      Expanded(
                        child: Text(
                          routeError,

                          style:
                              const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
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

// ================================================================
// RISK INFORMATION WIDGET
// ================================================================

class _RiskInfo
    extends StatelessWidget {
  final IconData icon;

  final String title;

  final String value;

  const _RiskInfo({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.blue,
          size: 20,
        ),

        const SizedBox(
          height: 4,
        ),

        Text(
          title,

          style:
              const TextStyle(
            color: Colors.grey,
            fontSize: 10,
          ),
        ),

        const SizedBox(
          height: 2,
        ),

        Text(
          value,

          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
