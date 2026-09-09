
import 'package:flutter/material.dart';
import 'map_screen.dart';

class TravelModeScreen extends StatefulWidget {
  const TravelModeScreen({super.key});

  @override
  State<TravelModeScreen> createState() =>
      _TravelModeScreenState();
}

class _TravelModeScreenState extends State<TravelModeScreen> {
  String? selectedMode;

  final List<Map<String, dynamic>> modes = [
    {
      'title': 'Car',
      'subtitle': 'Personal vehicle',
      'icon': Icons.directions_car,
    },
    {
      'title': 'Bike',
      'subtitle': 'Two wheeler',
      'icon': Icons.two_wheeler,
    },
    {
      'title': 'Bus',
      'subtitle': 'Public transport',
      'icon': Icons.directions_bus,
    },
    {
      'title': 'Walking',
      'subtitle': 'Pedestrian',
      'icon': Icons.directions_walk,
    },
    {
      'title': 'Ambulance',
      'subtitle': 'Emergency',
      'icon': Icons.local_hospital,
    },
    {
      'title': 'Rescue',
      'subtitle': 'Rescue vehicle',
      'icon': Icons.emergency,
    },
  ];

  void continueToLocation() {
    if (selectedMode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a transport mode first.',
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          travelMode: selectedMode!,
          selectionMode: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Transport Mode',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const Text(
                'How are you travelling?',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Choose your transport mode before selecting your route.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 25),

              Expanded(
                child: GridView.builder(
                  itemCount: modes.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 1.05,
                  ),
                  itemBuilder: (context, index) {
                    final mode = modes[index];

                    final title =
                        mode['title'] as String;

                    final subtitle =
                        mode['subtitle'] as String;

                    final icon =
                        mode['icon'] as IconData;

                    final isSelected =
                        selectedMode == title;

                    return InkWell(
                      borderRadius:
                          BorderRadius.circular(20),
                      onTap: () {
                        setState(() {
                          selectedMode = title;
                        });
                      },
                      child: AnimatedContainer(
                        duration:
                            const Duration(
                          milliseconds: 200,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.blue
                                  .withOpacity(0.10)
                              : Colors.white,
                          borderRadius:
                              BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? Colors.blue
                                : Colors.grey.shade300,
                            width:
                                isSelected ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withOpacity(0.05),
                              blurRadius: 8,
                              offset:
                                  const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            Center(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    icon,
                                    size: 42,
                                    color: isSelected
                                        ? Colors.blue
                                        : Colors.blueGrey,
                                  ),

                                  const SizedBox(
                                    height: 12,
                                  ),

                                  Text(
                                    title,
                                    style:
                                        const TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),

                                  const SizedBox(
                                    height: 4,
                                  ),

                                  Text(
                                    subtitle,
                                    style:
                                        TextStyle(
                                      color: Colors
                                          .grey.shade600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            if (isSelected)
                              const Positioned(
                                right: 10,
                                top: 10,
                                child: Icon(
                                  Icons.check_circle,
                                  color: Colors.blue,
                                  size: 22,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: continueToLocation,
                  icon: const Icon(
                    Icons.arrow_forward,
                  ),
                  label: const Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
