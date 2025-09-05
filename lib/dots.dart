import 'dart:math';
import 'package:flutter/material.dart';

class RotatingDotsIndicator extends StatefulWidget {
  const RotatingDotsIndicator({
    super.key,
    this.size = 50.0,
    this.color = const Color.fromARGB(255, 185, 139, 0),
  });

  final double size;
  final Color color;

  @override
  State<RotatingDotsIndicator> createState() => _RotatingDotsIndicatorState();
}

class _RotatingDotsIndicatorState extends State<RotatingDotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat();

    _rotation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildDot(double angle) {
    final radius = widget.size / 3;
    return Transform.translate(
      offset: Offset(
        radius * cos(angle),
        radius * sin(angle),
      ),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _rotation,
        builder: (_, __) {
          final angle = _rotation.value * 2 * pi;
          return Stack(
            alignment: Alignment.center,
            children: [
              _buildDot(angle),
              _buildDot(angle + 2 * pi / 3),
              _buildDot(angle + 4 * pi / 3),
            ],
          );
        },
      ),
    );
  }
}
