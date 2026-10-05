import 'package:flutter/material.dart';

import 'theme.dart';

/// Everything that changes between the pistak. apps of each sport.
/// The roller-hockey app is the first one; football, basketball… reuse the
/// same code with another [SportBrand] (dot colour, header image, sport id).
class SportBrand {
  const SportBrand({
    required this.sportId,
    required this.appName,
    required this.heroAsset,
    required this.accent,
  });

  /// Matches `Sports` ids (domain/sport).
  final String sportId;

  /// Name under the icon / in the task switcher.
  final String appName;

  /// Full-width header image of the home and welcome screens.
  final String heroAsset;

  /// Colour of the dot in the "pistak." wordmark.
  final Color accent;
}

const rollerHockeyBrand = SportBrand(
  sportId: 'roller_hockey',
  appName: 'pistak. hockey',
  heroAsset: 'assets/sports/hockey_hero.jpg',
  accent: PistakColors.accent,
);

/// The brand of this build.
const currentBrand = rollerHockeyBrand;
