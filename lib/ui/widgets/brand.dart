import 'package:flutter/material.dart';

import '../../app/sport_brand.dart';
import '../../app/theme.dart';

/// "pistak." — white lowercase wordmark with the sport-coloured dot.
class PistakWordmark extends StatelessWidget {
  const PistakWordmark({super.key, this.size = 40, this.color = Colors.white});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dot = size * 0.2;
    // Poppins: ascender 1050, descender 350 (units/em). With height 1.0 the
    // line box is ascent+descent, so the baseline sits 0.25·size above the
    // bottom: that's where the dot rests (no baseline/intrinsic tricks, so
    // it works inside any layout).
    return Semantics(
      label: 'pistak',
      excludeSemantics: true,
      // Shrinks (never overflows) on very narrow screens.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'pistak',
              textScaler: TextScaler.noScaling, // it's a logo
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: size,
                height: 1.0,
                letterSpacing: -size * 0.03,
                color: color,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: size * 0.06, bottom: size * 0.25),
              child: SizedBox.square(
                dimension: dot,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: currentBrand.accent, shape: BoxShape.circle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width header with the sport image, the wordmark and the sport name.
class SportHeader extends StatelessWidget {
  const SportHeader({super.key, required this.sportName, this.height = 210});
  final String sportName;
  final double height;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: height + top,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            currentBrand.heroAsset,
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
            excludeFromSemantics: true,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.55, 1.0],
                colors: [
                  Color(0x660B0F14),
                  Color(0x000B0F14),
                  PistakColors.background,
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const PistakWordmark(size: 42),
                Text(
                  sportName,
                  style: TextStyle(
                    color: currentBrand.accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
