import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/location_service.dart';

class RescueScreen extends StatefulWidget {
  const RescueScreen({super.key});

  @override
  State<RescueScreen> createState() => _RescueScreenState();
}

class _RescueScreenState extends State<RescueScreen> {
  static const primaryColor = Color(0xFF2563EB);
  static const darkColor = Color(0xFF1E3A8A);

  bool loading = true;
  bool rescueRequested = false;

  Position? currentPosition;
  String locationName = 'Getting your location...';
  String riskLevel = 'Checking flood risk...';

  @override
  void initState() {
    super.initState();
    _initializeRescue();
  }

  Future<void> _initializeRescue() async {
    try {
      final position = await _getCurrentLocation();

      if (!mounted) return;

      setState(() {
        currentPosition = position;
        locationName =
            'Latitude: ${position.latitude.toStringAsFixed(5)}\n'
            'Longitude: ${position.longitude.toStringAsFixed(5)}';
        riskLevel = 'Location detected';
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
        locationName = 'Unable to get current location';
        riskLevel = 'Location permission required';
      });
    }
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();

      throw Exception('Location service disabled');
    }

    LocationPermission permission =
        await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  void _requestRescue() {
    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Current location is not available yet.',
          ),
        ),
      );
      return;
    }

    setState(() {
      rescueRequested = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: darkColor,
        title: const Text(
          'Emergency Rescue',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEmergencyHeader(),

              const SizedBox(height: 20),

              _buildLocationCard(),

              const SizedBox(height: 16),

              _buildRiskCard(),

              const SizedBox(height: 20),

              if (rescueRequested)
                _buildSuccessCard()
              else
                _buildRescueButton(),

              const SizedBox(height: 20),

              _buildPrototypeNotice(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmergencyHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFEF4444),
            Color(0xFFB91C1C),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.emergency,
            color: Colors.white,
            size: 42,
          ),
          SizedBox(height: 12),
          Text(
            'Emergency Rescue',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'HydroPulse will use your current location '
            'to create a rescue request.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on,
              color: primaryColor,
              size: 28,
            ),
          ),

          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Current Location',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),

                const SizedBox(height: 7),

                if (loading)
                  const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Detecting GPS location...',
                        style: TextStyle(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    locationName,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.orange.shade100,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.water,
              color: Colors.orange,
              size: 27,
            ),
          ),

          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'Flood / Risk Status',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  riskLevel,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRescueButton() {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: ElevatedButton.icon(
        onPressed: loading ? null : _requestRescue,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade400,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        icon: const Icon(
          Icons.emergency,
          size: 27,
        ),
        label: const Text(
          'REQUEST RESCUE',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.green.shade200,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              color: Colors.white,
              size: 32,
            ),
          ),

          const SizedBox(height: 14),

          const Text(
            'Rescue Request Created',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Your current location has been captured '
            'for the rescue request.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Rescue-safe routing will be connected next.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.route),
              label: const Text(
                'View Rescue-Safe Route',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrototypeNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.blue.shade100,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.blue.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Prototype: This creates a rescue request inside '
              'HydroPulse. It does not currently dispatch a '
              'real emergency team.',
              style: TextStyle(
                color: Colors.blue.shade900,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}