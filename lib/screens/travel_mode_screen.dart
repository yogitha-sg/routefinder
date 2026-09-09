import 'package:flutter/material.dart';
import 'map_screen.dart';

class TravelModeScreen extends StatelessWidget {
  const TravelModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final modes = [
      {
        'title': 'Personal Vehicle',
        'icon': Icons.directions_car,
      },
      {
        'title': 'Ambulance',
        'icon': Icons.local_hospital,
      },
      {
        'title': 'Rescue',
        'icon': Icons.emergency,
      },
      {
        'title': 'Public Transport',
        'icon': Icons.directions_bus,
      },
      {
        'title': 'Pedestrian',
        'icon': Icons.directions_walk,
      },
      {
        'title': 'Shared Commute',
        'icon': Icons.people,
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Travel Mode'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How are you travelling?',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'HydroPulse will calculate the safest route for your travel mode.',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 15,
              ),
            ),

            const SizedBox(height: 24),

            Expanded(
              child: GridView.builder(
                itemCount: modes.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.15,
                ),
                itemBuilder: (context, index) {
                  final mode = modes[index];

                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MapScreen(
                            travelMode: mode['title'] as String,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.grey.shade200,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            mode['icon'] as IconData,
                            size: 42,
                            color: Colors.blue,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            mode['title'] as String,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
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
      ),
    );
  }
}