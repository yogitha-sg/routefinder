import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../models/road_segment.dart';
import '../services/risk_service.dart';
import '../services/weather_service.dart';
import '../services/route_service.dart';
import '../services/location_service.dart';

class MapScreen extends StatefulWidget {
  final String travelMode;

  const MapScreen({
    super.key,
    required this.travelMode,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // ============================================================
  // MAP CONTROLLER
  // ============================================================

  final MapController mapController = MapController();

  // ============================================================
  // WEATHER VARIABLES
  // ============================================================

  double rainfall = 0;

  bool isLoadingWeather = true;

  String weatherError = '';

  // ============================================================
  // LOCATION VARIABLES
  // ============================================================

  Position? currentPosition;

  bool isLoadingLocation = false;

  String locationError = '';

  // ============================================================
  // ROAD VARIABLES
  // ============================================================

  late List<RoadSegment> roads;

  RoadSegment? recommendedRoad;

  // ============================================================
  // INIT STATE
  // ============================================================

  @override
  void initState() {
    super.initState();

    // Chennai road segments
    roads = [
      RoadSegment(
        name: 'Velachery Main Road',
        elevation: 2.1,
        drainageDistance: 180,
        points: [
          LatLng(12.9815, 80.2180),
          LatLng(12.9875, 80.2200),
          LatLng(12.9940, 80.2230),
        ],
      ),

      RoadSegment(
        name: 'Mudichur Link',
        elevation: 1.8,
        drainageDistance: 190,
        points: [
          LatLng(12.9250, 80.1050),
          LatLng(12.9300, 80.1120),
          LatLng(12.9380, 80.1200),
        ],
      ),

      RoadSegment(
        name: 'OMR Perungudi',
        elevation: 4.5,
        drainageDistance: 90,
        points: [
          LatLng(12.9550, 80.2450),
          LatLng(12.9650, 80.2500),
          LatLng(12.9750, 80.2550),
        ],
      ),

      RoadSegment(
        name: 'Anna Salai',
        elevation: 7.8,
        drainageDistance: 60,
        points: [
          LatLng(13.0400, 80.2500),
          LatLng(13.0500, 80.2550),
          LatLng(13.0600, 80.2600),
        ],
      ),

      RoadSegment(
        name: 'Kathipara Corridor',
        elevation: 11.5,
        drainageDistance: 40,
        points: [
          LatLng(13.0100, 80.1950),
          LatLng(13.0150, 80.2050),
          LatLng(13.0200, 80.2150),
        ],
      ),
    ];

    // Fetch live rainfall.
    fetchWeather();
  }

  // ============================================================
  // FETCH WEATHER
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
        weatherError = '';
      });

      updateRisk();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoadingWeather = false;
        weatherError = 'Unable to fetch rainfall data';
      });

      // Still calculate risk using the default rainfall value.
      updateRisk();
    }
  }

  // ============================================================
  // GET CURRENT LOCATION
  // ============================================================

  Future<void> getCurrentLocation() async {
    if (isLoadingLocation) return;

    setState(() {
      isLoadingLocation = true;
      locationError = '';
    });

    try {
      // Get current GPS location using your LocationService.
      final position = await LocationService.getCurrentLocation();

      if (!mounted) return;

      setState(() {
        currentPosition = position;
        isLoadingLocation = false;
        locationError = '';
      });

      // ----------------------------------------------------------
      // MOVE MAP TO USER LOCATION
      // ----------------------------------------------------------

      mapController.move(
        LatLng(
          position.latitude,
          position.longitude,
        ),
        14.0,
      );

      // ----------------------------------------------------------
      // IMPORTANT:
      // GO TO NEXT SCREEN AFTER LOCATION IS SUCCESSFULLY FOUND
      // ----------------------------------------------------------

      await Future.delayed(
        const Duration(milliseconds: 500),
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LocationResultScreen(
            latitude: position.latitude,
            longitude: position.longitude,
            travelMode: widget.travelMode,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoadingLocation = false;

        locationError = e
            .toString()
            .replaceFirst('Exception: ', '');
      });

      // Show the error clearly to the user.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            locationError.isEmpty
                ? 'Unable to get your location'
                : locationError,
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ============================================================
  // UPDATE ROAD RISK
  // ============================================================

  void updateRisk() {
    for (final road in roads) {
      road.riskLevel = RiskService.calculateRisk(
        rainfall: rainfall,
        elevation: road.elevation,
        drainageDistance: road.drainageDistance,
      );
    }

    // Find safest available road.
    recommendedRoad = RouteService.findSafestRoad(roads);

    if (mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // RISK COLOR
  // ============================================================

  Color getRiskColor(RiskLevel level) {
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

  String getRiskText(RiskLevel level) {
    switch (level) {
      case RiskLevel.safe:
        return 'SAFE';

      case RiskLevel.moderate:
        return 'MODERATE';

      case RiskLevel.impassable:
        return 'IMPASSABLE';
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ========================================================
      // APP BAR
      // ========================================================

      appBar: AppBar(
        title: Text(widget.travelMode),
        centerTitle: true,
        actions: [
          // Refresh weather button.
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh rainfall',
            onPressed: isLoadingWeather
                ? null
                : () {
                    setState(() {
                      isLoadingWeather = true;
                      weatherError = '';
                    });

                    fetchWeather();
                  },
          ),
        ],
      ),

      // ========================================================
      // BODY
      // ========================================================

      body: Stack(
        children: [
          // ====================================================
          // MAP
          // ====================================================

          FlutterMap(
            mapController: mapController,

            options: const MapOptions(
              initialCenter: LatLng(
                13.0827,
                80.2707,
              ),
              initialZoom: 11.5,
            ),

            children: [
              // ------------------------------------------------
              // OPEN STREET MAP
              // ------------------------------------------------

              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',

                userAgentPackageName:
                    'com.example.hydropulse',
              ),

              // ------------------------------------------------
              // FLOOD RISK ROAD SEGMENTS
              // ------------------------------------------------

              PolylineLayer(
                polylines: roads.map((road) {
                  final isRecommended =
                      recommendedRoad == road;

                  return Polyline(
                    points: road.points,

                    // Recommended road is thicker.
                    strokeWidth:
                        isRecommended ? 11 : 7,

                    // Recommended route is blue.
                    // Other roads use their risk color.
                    color: isRecommended
                        ? Colors.blue
                        : getRiskColor(
                            road.riskLevel,
                          ),
                  );
                }).toList(),
              ),

              // ------------------------------------------------
              // USER LOCATION MARKER
              // ------------------------------------------------

              if (currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        currentPosition!.latitude,
                        currentPosition!.longitude,
                      ),

                      width: 55,
                      height: 55,

                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue
                              .withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),

                        child: const Center(
                          child: Icon(
                            Icons.my_location,
                            color: Colors.blue,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ====================================================
          // RECOMMENDED ROUTE CARD
          // ====================================================

          if (!isLoadingWeather &&
              recommendedRoad != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,

              child: Card(
                elevation: 6,

                child: Padding(
                  padding:
                      const EdgeInsets.all(14),

                  child: Row(
                    children: [
                      // Route icon.
                      Container(
                        width: 44,
                        height: 44,

                        decoration: BoxDecoration(
                          color: Colors.blue
                              .withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),

                        child: const Icon(
                          Icons.route,
                          color: Colors.blue,
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Route information.
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,

                          children: [
                            const Text(
                              'Recommended Route',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 4),

                            Text(
                              recommendedRoad!.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 3),

                            Text(
                              getRiskText(
                                recommendedRoad!
                                    .riskLevel,
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    FontWeight.bold,
                                color: getRiskColor(
                                  recommendedRoad!
                                      .riskLevel,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ====================================================
          // LOCATION ERROR
          // ====================================================

          if (locationError.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 185,

              child: Card(
                elevation: 5,

                child: Padding(
                  padding:
                      const EdgeInsets.all(10),

                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_off,
                        color: Colors.red,
                      ),

                      const SizedBox(width: 8),

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

          // ====================================================
          // MY LOCATION BUTTON
          // ====================================================

          Positioned(
            right: 16,
            bottom: 330,

            child: FloatingActionButton(
              heroTag: 'locationButton',

              backgroundColor: Colors.white,

              foregroundColor: Colors.blue,

              onPressed: isLoadingLocation
                  ? null
                  : getCurrentLocation,

              child: isLoadingLocation
                  ? const SizedBox(
                      width: 22,
                      height: 22,

                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.my_location,
                    ),
            ),
          ),

          // ====================================================
          // BOTTOM WEATHER CARD
          // ====================================================

          Positioned(
            left: 16,
            right: 16,
            bottom: 20,

            child: Card(
              elevation: 6,

              child: Padding(
                padding:
                    const EdgeInsets.all(16),

                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,

                  children: [
                    // ------------------------------------------
                    // CURRENT RAINFALL
                    // ------------------------------------------

                    Row(
                      children: [
                        const Icon(
                          Icons.water_drop,
                          color: Colors.blue,
                        ),

                        const SizedBox(width: 8),

                        const Text(
                          'Current Rainfall',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const Spacer(),

                        if (isLoadingWeather)
                          const SizedBox(
                            width: 20,
                            height: 20,

                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        else
                          Text(
                            '${rainfall.toStringAsFixed(1)} mm',
                            style:
                                const TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                      ],
                    ),

                    // ------------------------------------------
                    // WEATHER ERROR
                    // ------------------------------------------

                    if (weatherError.isNotEmpty) ...[
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber,
                            size: 18,
                            color: Colors.red,
                          ),

                          const SizedBox(width: 6),

                          Expanded(
                            child: Text(
                              weatherError,
                              style:
                                  const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 12),

                    // ------------------------------------------
                    // LOCATION
                    // ------------------------------------------

                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 20,
                          color: Colors.red,
                        ),

                        const SizedBox(width: 6),

                        Text(
                          currentPosition == null
                              ? 'Chennai'
                              : 'Current Location',
                          style: const TextStyle(
                            fontWeight:
                                FontWeight.w500,
                          ),
                        ),

                        const Spacer(),

                        const Text(
                          'Live Weather',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    const Divider(),

                    const SizedBox(height: 10),

                    // ------------------------------------------
                    // RISK LEGEND
                    // ------------------------------------------

                    const Row(
                      mainAxisAlignment:
                          MainAxisAlignment
                              .spaceAround,

                      children: [
                        _Legend(
                          color: Colors.green,
                          text: 'Safe',
                        ),

                        _Legend(
                          color: Colors.orange,
                          text: 'Moderate',
                        ),

                        _Legend(
                          color: Colors.red,
                          text: 'Impassable',
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // ------------------------------------------
                    // RECOMMENDED ROUTE LEGEND
                    // ------------------------------------------

                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,

                      children: [
                        Container(
                          width: 24,
                          height: 5,

                          decoration:
                              BoxDecoration(
                            color: Colors.blue,
                            borderRadius:
                                BorderRadius.circular(
                              10,
                            ),
                          ),
                        ),

                        const SizedBox(width: 6),

                        const Text(
                          'Recommended Route',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                FontWeight.w500,
                          ),
                        ),
                      ],
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
// LOCATION RESULT SCREEN
// ============================================================
//
// This is the screen that opens after the location button
// successfully gets the user's location.
//
// Later, you can replace this with your actual next screen.
// ============================================================

class LocationResultScreen extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String travelMode;

  const LocationResultScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.travelMode,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Confirmed'),
        centerTitle: true,
      ),

      body: Padding(
        padding: const EdgeInsets.all(24),

        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [
            Container(
              width: 90,
              height: 90,

              decoration: BoxDecoration(
                color: Colors.green
                    .withOpacity(0.12),
                shape: BoxShape.circle,
              ),

              child: const Icon(
                Icons.location_on,
                color: Colors.green,
                size: 55,
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Location Detected!',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'Your current location has been successfully detected.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 24),

            Card(
              elevation: 3,

              child: Padding(
                padding:
                    const EdgeInsets.all(18),

                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.navigation,
                          color: Colors.blue,
                        ),

                        const SizedBox(width: 10),

                        const Text(
                          'Latitude',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const Spacer(),

                        Text(
                          latitude.toStringAsFixed(6),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        const Icon(
                          Icons.navigation,
                          color: Colors.blue,
                        ),

                        const SizedBox(width: 10),

                        const Text(
                          'Longitude',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const Spacer(),

                        Text(
                          longitude.toStringAsFixed(6),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        const Icon(
                          Icons.directions_car,
                          color: Colors.blue,
                        ),

                        const SizedBox(width: 10),

                        const Text(
                          'Travel Mode',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const Spacer(),

                        Text(travelMode),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 52,

              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                },

                icon: const Icon(
                  Icons.arrow_back,
                ),

                label: const Text(
                  'Back to Map',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// LEGEND WIDGET
// ============================================================

class _Legend extends StatelessWidget {
  final Color color;
  final String text;

  const _Legend({
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,

          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),

        const SizedBox(width: 5),

        Text(text),
      ],
    );
  }
}