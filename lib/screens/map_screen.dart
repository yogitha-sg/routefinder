import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../services/risk_service.dart';
import '../services/weather_service.dart';
import '../services/route_service.dart';
import '../services/location_service.dart';
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

  double rainfall = 0;

  bool isLoadingWeather = true;

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
      final position =
          await LocationService.getCurrentLocation();

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
        locationError = e
            .toString()
            .replaceFirst('Exception: ', '');
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
  // FIND REAL ROUTES
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
    });

    try {
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
        isLoadingRoutes = false;
        routeCalculated = true;
      });

      // Select safest route
      selectedRouteIndex = calculateSafestRouteIndex();

      if (selectedRouteIndex >= routes.length) {
        selectedRouteIndex = 0;
      }

      setState(() {
        safestRoute = routes[selectedRouteIndex];
      });

      fitMapToRoute(routes[selectedRouteIndex]);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${routes.length} route${routes.length == 1 ? '' : 's'} found.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoadingRoutes = false;
        routeCalculated = false;
        routeError = e
            .toString()
            .replaceFirst('Exception: ', '');
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
  // SAFEST ROUTE CALCULATION
  // ============================================================

  int calculateSafestRouteIndex() {
    if (routes.isEmpty) {
      return 0;
    }

    int bestIndex = 0;
    double bestScore = double.infinity;

    for (int i = 0; i < routes.length; i++) {
      final route = routes[i];

      final score = calculateRouteRiskScore(route);

      if (score < bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  // ============================================================
  // ROUTE RISK SCORE
  //
  // This is a prototype risk model.
  //
  // Later this can be replaced with:
  // rainfall + elevation + drainage + live flood data
  // ============================================================

  double calculateRouteRiskScore(RouteOption route) {
    final distanceKm = route.distanceKm;

    double score = 0;

    // Rainfall contribution
    if (rainfall >= 100) {
      score += 70;
    } else if (rainfall >= 50) {
      score += 45;
    } else if (rainfall >= 20) {
      score += 25;
    } else {
      score += 10;
    }

    // Longer route gets a small penalty.
    score += distanceKm * 2;

    // Longer routes are not automatically unsafe.
    // The rainfall component remains dominant.
    return score;
  }

  // ============================================================
  // ROUTE RISK LEVEL
  // ============================================================

  RiskLevel routeRiskLevel(RouteOption route) {
    final score = calculateRouteRiskScore(route);

    if (score >= 70) {
      return RiskLevel.impassable;
    }

    if (score >= 35) {
      return RiskLevel.moderate;
    }

    return RiskLevel.safe;
  }

  // ============================================================
  // RISK COLOR
  // ============================================================

  Color riskColor(RiskLevel level) {
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

  String riskText(RiskLevel level) {
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
  // FIT MAP TO SELECTED ROUTE
  // ============================================================

  void fitMapToRoute(RouteOption route) {
    if (route.coordinates.isEmpty) return;

    double minLat = route.coordinates.first[0];
    double maxLat = route.coordinates.first[0];

    double minLng = route.coordinates.first[1];
    double maxLng = route.coordinates.first[1];

    for (final point in route.coordinates) {
      final lat = point[0];
      final lng = point[1];

      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;

      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    if (currentPosition != null) {
      minLat = minLat <
              currentPosition!.latitude
          ? minLat
          : currentPosition!.latitude;

      maxLat = maxLat >
              currentPosition!.latitude
          ? maxLat
          : currentPosition!.latitude;

      minLng = minLng <
              currentPosition!.longitude
          ? minLng
          : currentPosition!.longitude;

      maxLng = maxLng >
              currentPosition!.longitude
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

    mapController.move(center, calculateZoom());
  }

  double calculateZoom() {
    if (currentPosition == null ||
        destination == null) {
      return 13;
    }

    final distance = const Distance().as(
      LengthUnit.Kilometer,
      LatLng(
        currentPosition!.latitude,
        currentPosition!.longitude,
      ),
      destination!,
    );

    if (distance < 2) return 15;

    if (distance < 5) return 14;

    if (distance < 10) return 13;

    if (distance < 20) return 12;

    return 11;
  }

  // ============================================================
  // SELECT A DIFFERENT ROUTE
  // ============================================================

  void selectRoute(int index) {
    if (index < 0 || index >= routes.length) {
      return;
    }

    setState(() {
      selectedRouteIndex = index;
      safestRoute = routes[index];
    });

    fitMapToRoute(routes[index]);
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

  String formatDistance(double km) {
    if (km < 1) {
      return '${(km * 1000).round()} m';
    }

    return '${km.toStringAsFixed(1)} km';
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
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
              initialCenter:
                  const LatLng(
                13.0827,
                80.2707,
              ),

              initialZoom: 11.5,

              onTap: (tapPosition, point) {
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
              // REAL ROUTES
              // ==================================================

              if (routes.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (int i = 0;
                        i < routes.length;
                        i++)
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
                                ? 8
                                : 5,

                        color:
                            i == selectedRouteIndex
                                ? Colors.blue
                                : riskColor(
                                    routeRiskLevel(
                                      routes[i],
                                    ),
                                  ),
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
                        currentPosition!
                            .latitude,
                        currentPosition!
                            .longitude,
                      ),

                      width: 55,
                      height: 55,

                      child: Container(
                        decoration:
                            BoxDecoration(
                          color: Colors.blue
                              .withOpacity(0.15),
                          shape:
                              BoxShape.circle,
                        ),

                        child:
                            const Icon(
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

                    const SizedBox(width: 10),

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
                            style:
                                const TextStyle(
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

                      const SizedBox(height: 7),

                      Row(
                        children: [
                          const Icon(
                            Icons.my_location,
                            color: Colors.blue,
                            size: 18,
                          ),

                          const SizedBox(width: 6),

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

                      const SizedBox(height: 5),

                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 18,
                          ),

                          const SizedBox(width: 6),

                          Expanded(
                            child: Text(
                              destination == null
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
                  color: Colors.black
                      .withOpacity(0.18),

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

                            SizedBox(height: 15),

                            Text(
                              'Finding safest routes...',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),

                            SizedBox(height: 5),

                            Text(
                              'Analyzing real road paths',
                              style: TextStyle(
                                color: Colors.grey,
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
                    : 310,

            child:
                FloatingActionButton(
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

                child:
                    ElevatedButton.icon(
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
              left: 12,
              right: 12,
              bottom: 15,

              child: Card(
                elevation: 9,

                child: Padding(
                  padding:
                      const EdgeInsets.all(15),

                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,

                    children: [
                      // ------------------------------------------
                      // HEADER
                      // ------------------------------------------

                      Row(
                        children: [
                          Container(
                            width: 43,
                            height: 43,

                            decoration:
                                BoxDecoration(
                              color: Colors.green
                                  .withOpacity(
                                      0.12),

                              shape:
                                  BoxShape.circle,
                            ),

                            child:
                                const Icon(
                              Icons
                                  .verified_user,
                              color:
                                  Colors.green,
                            ),
                          ),

                          const SizedBox(
                            width: 10,
                          ),

                          const Expanded(
                            child: Text(
                              'Safest Route Found',
                              style:
                                  TextStyle(
                                fontSize: 17,
                                fontWeight:
                                    FontWeight
                                        .bold,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // ------------------------------------------
                      // ROUTE NUMBER
                      // ------------------------------------------

                      Text(
                        'Route ${selectedRouteIndex + 1}',
                        style:
                            const TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 7),

                      // ------------------------------------------
                      // RISK
                      // ------------------------------------------

                      Row(
                        children: [
                          Icon(
                            Icons.shield,
                            size: 18,
                            color:
                                riskColor(
                              routeRiskLevel(
                                safestRoute!,
                              ),
                            ),
                          ),

                          const SizedBox(
                            width: 5,
                          ),

                          Text(
                            riskText(
                              routeRiskLevel(
                                safestRoute!,
                              ),
                            ),

                            style:
                                TextStyle(
                              fontWeight:
                                  FontWeight
                                      .bold,
                              color:
                                  riskColor(
                                routeRiskLevel(
                                  safestRoute!,
                                ),
                              ),
                            ),
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

                      const Divider(
                        height: 20,
                      ),

                      // ------------------------------------------
                      // DISTANCE / TIME
                      // ------------------------------------------

                      Row(
                        children: [
                          Expanded(
                            child:
                                _RiskInfo(
                              icon:
                                  Icons
                                      .route,
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
                                  Icons
                                      .access_time,
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
                                  Icons
                                      .water_drop,
                              title:
                                  'Rainfall',
                              value:
                                  '${rainfall.toStringAsFixed(1)} mm',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // ------------------------------------------
                      // ALTERNATIVE ROUTES
                      // ------------------------------------------

                      if (routes.length > 1)
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,

                          children: [
                            const Text(
                              'Available Routes',
                              style:
                                  TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),

                            const SizedBox(
                              height: 7,
                            ),

                            SizedBox(
                              height: 48,

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
                                    (_, __) =>
                                        const SizedBox(
                                  width: 7,
                                ),

                                itemBuilder:
                                    (context,
                                        index) {
                                  final route =
                                      routes[
                                          index];

                                  final risk =
                                      routeRiskLevel(
                                    route,
                                  );

                                  final selected =
                                      index ==
                                          selectedRouteIndex;

                                  return GestureDetector(
                                    onTap: () =>
                                        selectRoute(
                                      index,
                                    ),

                                    child:
                                        Container(
                                      padding:
                                          const EdgeInsets
                                              .symmetric(
                                        horizontal:
                                            12,
                                      ),

                                      decoration:
                                          BoxDecoration(
                                        color: selected
                                            ? Colors
                                                .blue
                                                .withOpacity(
                                                    0.10)
                                            : Colors
                                                .grey
                                                .withOpacity(
                                                    0.08),

                                        borderRadius:
                                            BorderRadius
                                                .circular(
                                                    12),

                                        border:
                                            Border.all(
                                          color:
                                              selected
                                                  ? Colors
                                                      .blue
                                                  : Colors
                                                      .grey
                                                      .shade300,
                                        ),
                                      ),

                                      child:
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
                                                    ? Colors
                                                        .blue
                                                    : Colors
                                                        .grey,
                                            size: 18,
                                          ),

                                          const SizedBox(
                                            width:
                                                5,
                                          ),

                                          Text(
                                            'R${index + 1}',
                                            style:
                                                const TextStyle(
                                              fontWeight:
                                                  FontWeight
                                                      .bold,
                                            ),
                                          ),

                                          const SizedBox(
                                            width:
                                                6,
                                          ),

                                          Text(
                                            formatDistance(
                                              route
                                                  .distanceKm,
                                            ),
                                            style:
                                                const TextStyle(
                                              fontSize:
                                                  11,
                                            ),
                                          ),

                                          const SizedBox(
                                            width:
                                                6,
                                          ),

                                          Icon(
                                            Icons
                                                .shield,
                                            size:
                                                14,
                                            color:
                                                riskColor(
                                              risk,
                                            ),
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
          // ERROR
          // ======================================================

          if (locationError.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: 90,

              child: Card(
                color: Colors.red.shade50,

                child: Padding(
                  padding:
                      const EdgeInsets.all(10),

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
                color: Colors.red.shade50,

                child: Padding(
                  padding:
                      const EdgeInsets.all(10),

                  child: Row(
                    children: [
                      const Icon(
                        Icons
                            .wrong_location,
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

class _RiskInfo extends StatelessWidget {
  final IconData icon;

  final String title;

  final String value;

  const _RiskInfo({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.blue,
          size: 20,
        ),

        const SizedBox(height: 4),

        Text(
          title,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 10,
          ),
        ),

        const SizedBox(height: 2),

        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}