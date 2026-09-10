import 'package:flutter/material.dart';
import 'travel_mode_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const primaryColor = Color(0xFF2563EB);
  static const darkColor = Color(0xFF102A56);
  static const inkColor = Color(0xFF0F1B2E);

  late final AnimationController _controller;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Staggered reveal helper: each element fades and rises into place
  // on its own slice of the single load-in timeline.
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
            offset: Offset(0, (1 - interval.value) * 18),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  void _goToTravelMode() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, animation, __) => const TravelModeScreen(),
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
      body: Stack(
        children: [
          // Ground-truth hydro backdrop: contour lines standing in for
          // elevation/flood-plain data, the one bold visual idea on this
          // screen. Everything else stays quiet around it.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _ContourPainter(
                    progress: Curves.easeOutCubic.transform(
                      _controller.value,
                    ),
                    lineColor: primaryColor,
                  ),
                );
              },
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(flex: 3),

                  // Logo with a slow pulse ring — reads as active
                  // detection/radar rather than decoration.
                  _reveal(
                    start: 0.0,
                    end: 0.55,
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _controller,
                            builder: (context, _) {
                              final t = _controller.value;
                              return Container(
                                width: 100 * (0.7 + 0.3 * t),
                                height: 100 * (0.7 + 0.3 * t),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: primaryColor.withOpacity(
                                      0.25 * (1 - t) + 0.05,
                                    ),
                                    width: 1.4,
                                  ),
                                ),
                              );
                            },
                          ),
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF3B82F6), darkColor],
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withOpacity(0.30),
                                  blurRadius: 22,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.alt_route_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  _reveal(
                    start: 0.15,
                    end: 0.65,
                    child: const Text(
                      'RouteFinder',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        height: 1.0,
                        color: inkColor,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  _reveal(
                    start: 0.22,
                    end: 0.72,
                    child: Text(
                      'Multi-hazard route and mobility guidance,\nbuilt on live weather and terrain data.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  _reveal(
                    start: 0.32,
                    end: 0.8,
                    child: const _SignalRow(),
                  ),

                  const Spacer(flex: 4),

                  _reveal(
                    start: 0.5,
                    end: 0.95,
                    child: GestureDetector(
                      onTapDown: (_) => setState(() => _pressed = true),
                      onTapUp: (_) => setState(() => _pressed = false),
                      onTapCancel: () => setState(() => _pressed = false),
                      onTap: _goToTravelMode,
                      child: AnimatedScale(
                        scale: _pressed ? 0.97 : 1.0,
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOut,
                        child: Container(
                          width: double.infinity,
                          height: 58,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(17),
                            gradient: const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Color(0xFF3B82F6), darkColor],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor.withOpacity(0.35),
                                blurRadius: 22,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Text(
                                'Get started',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
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

                  const SizedBox(height: 22),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three quiet data points instead of decorative "feature chips" —
/// each names something the app actually measures, not a marketing tag.
class _SignalRow extends StatelessWidget {
  const _SignalRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: _Signal(label: 'Rainfall', icon: Icons.water_drop_outlined),
        ),
        _Divider(),
        Expanded(
          child: _Signal(label: 'Elevation', icon: Icons.terrain_outlined),
        ),
        _Divider(),
        Expanded(
          child: _Signal(label: 'Road risk', icon: Icons.shield_outlined),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      color: Colors.grey.shade300,
    );
  }
}

class _Signal extends StatelessWidget {
  final String label;
  final IconData icon;

  const _Signal({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF2563EB)),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}

/// Faint elevation-contour backdrop. Lines drift in from a common origin
/// during the load-in animation, then hold still — the screen's one
/// deliberate motion moment, tied directly to what the app measures.
class _ContourPainter extends CustomPainter {
  final double progress;
  final Color lineColor;

  _ContourPainter({required this.progress, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = lineColor.withOpacity(0.07);

    // A handful of concentric, hand-tuned contour bands anchored to the
    // upper-right, evoking a topographic flood map rather than a generic
    // blurred circle.
    final origin = Offset(size.width * 0.92, size.height * 0.06);
    final radii = [0.16, 0.28, 0.40, 0.53, 0.67, 0.82];

    for (var i = 0; i < radii.length; i++) {
      final targetRadius = size.longestSide * radii[i];
      final animatedRadius =
          targetRadius * (0.85 + 0.15 * progress) - (1 - progress) * 40;

      final path = Path();
      const sweep = 220.0;
      final rect = Rect.fromCircle(
        center: origin,
        radius: animatedRadius.clamp(0, targetRadius),
      );
      path.addArc(
        rect,
        _deg(140),
        _deg(sweep),
      );
      canvas.drawPath(path, paint);
    }

    // Second faint cluster, lower-left, smaller — keeps the composition
    // balanced without competing for attention.
    final origin2 = Offset(size.width * 0.02, size.height * 0.96);
    final radii2 = [0.14, 0.24, 0.34];
    for (var i = 0; i < radii2.length; i++) {
      final targetRadius = size.longestSide * radii2[i];
      final animatedRadius =
          targetRadius * (0.85 + 0.15 * progress) - (1 - progress) * 30;

      final path = Path();
      final rect = Rect.fromCircle(
        center: origin2,
        radius: animatedRadius.clamp(0, targetRadius),
      );
      path.addArc(rect, _deg(-40), _deg(200));
      canvas.drawPath(
        path,
        paint..color = lineColor.withOpacity(0.05),
      );
    }
  }

  double _deg(double degrees) => degrees * 3.1415926535 / 180;

  @override
  bool shouldRepaint(covariant _ContourPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}