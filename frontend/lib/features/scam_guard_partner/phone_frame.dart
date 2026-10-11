import 'dart:math' as math;

import 'package:flutter/material.dart';

class PhoneFrame extends StatelessWidget {
  final Widget child;
  final double availableWidth;
  final double availableHeight;
  final bool compact;

  const PhoneFrame({
    super.key,
    required this.child,
    required this.availableWidth,
    required this.availableHeight,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final width = compact
        ? availableWidth
        : math.min(390.0, math.max(240.0, availableWidth - 32));
    final height = compact
        ? math.min(width * 2.05, availableHeight)
        : width * 2.05;
    final bezel = compact ? 0.0 : 10.0;

    return SizedBox(
      width: width,
      height: height,
      child: Container(
        padding: EdgeInsets.all(bezel),
        decoration: BoxDecoration(
          color: compact ? Colors.white : const Color(0xFF101114),
          borderRadius: BorderRadius.circular(compact ? 18 : 44),
          boxShadow: compact
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 34,
                    offset: const Offset(0, 18),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 16 : 34),
          child: Stack(
            children: [
              Column(
                children: [
                  const _DemoPayStatusBar(),
                  Expanded(
                    child: ColoredBox(color: Colors.white, child: child),
                  ),
                ],
              ),
              if (!compact)
                Positioned(
                  top: 4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 86,
                      height: 17,
                      decoration: BoxDecoration(
                        color: const Color(0xFF101114),
                        borderRadius: BorderRadius.circular(20),
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

class _DemoPayStatusBar extends StatelessWidget {
  const _DemoPayStatusBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      color: Colors.white,
      child: Row(
        children: [
          const Text(
            '9:41',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          const Icon(Icons.signal_cellular_alt, size: 13),
          const SizedBox(width: 4),
          const Icon(Icons.wifi, size: 14),
          const SizedBox(width: 4),
          const Icon(Icons.battery_full, size: 17),
        ],
      ),
    );
  }
}
