import 'package:flutter/material.dart';
import 'map_screen.dart';
import 'rescue_screen.dart';

class TravelModeScreen extends StatefulWidget {
  const TravelModeScreen({super.key});

  @override
  State<TravelModeScreen> createState() =>
      _TravelModeScreenState();
}

class _TravelModeScreenState extends State<TravelModeScreen>
    with SingleTickerProviderStateMixin {
  static const primaryColor = Color(0xFF2563EB);
  static const darkColor = Color(0xFF102A56);
  static const inkColor = Color(0xFF0F1B2E);

  String? selectedMode;
  bool _continuePressed = false;

  late final AnimationController _controller;

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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Same staggered-reveal helper used on the home screen, so the two
  // screens feel like one continuous experience rather than two apps.
  Widget _reveal({
    required Widget child,
    required double start,
    double end = 1.0,
  }) {
    final interval = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: interval,
      builder: (context, _) {
        return Opacity(
          opacity: interval.value,
          child: Transform.translate(
            offset: Offset(0, (1 - interval.value) * 14),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  void continueToLocation() {
    if (selectedMode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: darkColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: const Text(
            'Please select a transport mode first.',
          ),
        ),
      );
      return;
    }

    // 🚨 Rescue mode gets a dedicated emergency flow
    if (selectedMode == 'Rescue') {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: const Row(
              children: [
                Icon(
                  Icons.emergency,
                  color: Colors.red,
                  size: 30,
                ),
                SizedBox(width: 10),
                Text(
                  'Emergency Rescue',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: const Text(
              'Do you need emergency rescue assistance?\n\n'
              'HydroPulse will use your current location '
              'to create a rescue request.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.emergency),
                label: const Text('Request Rescue'),
                onPressed: () {
                  Navigator.pop(context);

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RescueScreen(),
                    ),
                  );
                },
              ),
            ],
          );
        },
      );

      return;
    }

    // Normal travel modes
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, animation, __) => MapScreen(
          travelMode: selectedMode!,
          selectionMode: true,
        ),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FF),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: inkColor,
        title: const Text(
          'Transport mode',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Faint contour backdrop, matching the home screen's hydro
          // motif, kept quiet enough not to compete with the grid.
          Positioned.fill(
            child: CustomPaint(
              painter: _ContourPainter(lineColor: primaryColor),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  _reveal(
                    start: 0.0,
                    end: 0.5,
                    child: const Text(
                      'How are you travelling?',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: inkColor,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  _reveal(
                    start: 0.08,
                    end: 0.55,
                    child: Text(
                      'Choose your transport mode before selecting your route.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                        height: 1.4,
                      ),
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

                        // Each tile's entrance is offset slightly by its
                        // grid position, so the grid fills in as one
                        // wave rather than popping in all at once.
                        final delay = 0.15 + (index * 0.05);

                        return _reveal(
                          start: delay.clamp(0.0, 0.7),
                          end: (delay + 0.35).clamp(0.0, 1.0),
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(22),
                            onTap: () {
                              setState(() {
                                selectedMode = title;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(
                                milliseconds: 220,
                              ),
                              curve: Curves.easeOut,
                              decoration: BoxDecoration(
                                gradient: isSelected
                                    ? const LinearGradient(
                                        begin: Alignment
                                            .topLeft,
                                        end: Alignment
                                            .bottomRight,
                                        colors: [
                                          Color(0xFF3B82F6),
                                          darkColor,
                                        ],
                                      )
                                    : null,
                                color: isSelected
                                    ? null
                                    : Colors.white,
                                borderRadius:
                                    BorderRadius.circular(22),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.transparent
                                      : Colors.grey.shade200,
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isSelected
                                        ? primaryColor
                                            .withOpacity(0.32)
                                        : Colors.black
                                            .withOpacity(0.03),
                                    blurRadius:
                                        isSelected ? 18 : 8,
                                    offset: Offset(
                                      0,
                                      isSelected ? 10 : 3,
                                    ),
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment
                                              .center,
                                      children: [
                                        Container(
                                          padding:
                                              const EdgeInsets
                                                  .all(10),
                                          decoration:
                                              BoxDecoration(
                                            shape: BoxShape
                                                .circle,
                                            color: isSelected
                                                ? Colors.white
                                                    .withOpacity(
                                                        0.18)
                                                : primaryColor
                                                    .withOpacity(
                                                        0.08),
                                          ),
                                          child: Icon(
                                            icon,
                                            size: 34,
                                            color: isSelected
                                                ? Colors.white
                                                : primaryColor,
                                          ),
                                        ),

                                        const SizedBox(
                                          height: 12,
                                        ),

                                        Text(
                                          title,
                                          style: TextStyle(
                                            fontWeight:
                                                FontWeight.bold,
                                            fontSize: 16,
                                            color: isSelected
                                                ? Colors.white
                                                : inkColor,
                                          ),
                                        ),

                                        const SizedBox(
                                          height: 4,
                                        ),

                                        Text(
                                          subtitle,
                                          style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                    .withOpacity(
                                                        0.85)
                                                : Colors.grey
                                                    .shade600,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  if (isSelected)
                                    Positioned(
                                      right: 10,
                                      top: 10,
                                      child: Container(
                                        padding:
                                            const EdgeInsets
                                                .all(2),
                                        decoration:
                                            const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                        ),
                                        child: const Icon(
                                          Icons.check_circle,
                                          color: primaryColor,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 14),

                  _reveal(
                    start: 0.75,
                    end: 1.0,
                    child: GestureDetector(
                      onTapDown: (_) =>
                          setState(() => _continuePressed = true),
                      onTapUp: (_) =>
                          setState(() => _continuePressed = false),
                      onTapCancel: () =>
                          setState(() => _continuePressed = false),
                      onTap: continueToLocation,
                      child: AnimatedScale(
                        scale: _continuePressed ? 0.97 : 1.0,
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOut,
                        child: Container(
                          width: double.infinity,
                          height: 58,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(17),
                            gradient: const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0xFF3B82F6),
                                darkColor,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor
                                    .withOpacity(0.35),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: const [
                              Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight:
                                      FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.1,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint elevation-contour backdrop, visually consistent with the home
/// screen's motif but static here — the grid itself carries the motion
/// on this screen, so the background stays still and out of the way.
class _ContourPainter extends CustomPainter {
  final Color lineColor;

  _ContourPainter({required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = lineColor.withOpacity(0.05);

    final origin = Offset(size.width * 0.05, size.height * -0.02);
    final radii = [0.18, 0.30, 0.42, 0.55];

    for (final r in radii) {
      final path = Path();
      final rect = Rect.fromCircle(
        center: origin,
        radius: size.longestSide * r,
      );
      path.addArc(rect, _deg(-30), _deg(200));
      canvas.drawPath(path, paint);
    }
  }

  double _deg(double degrees) => degrees * 3.1415926535 / 180;

  @override
  bool shouldRepaint(covariant _ContourPainter oldDelegate) => false;
}