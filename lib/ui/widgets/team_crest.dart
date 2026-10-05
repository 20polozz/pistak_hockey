import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/team/team.dart';

/// Crest image, or the team's initials on a coloured disc.
class TeamCrest extends StatelessWidget {
  const TeamCrest({super.key, required this.team, this.size = 40});
  final Team? team;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = team;
    final bytes = t?.crest;
    if (bytes != null) {
      return ClipOval(
        child: Image.memory(bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true),
      );
    }
    final name = (t?.shortName ?? t?.name ?? '?').trim();
    final initials = name.isEmpty
        ? '?'
        : name
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: PistakColors.surfaceHigh,
      child: Text(initials,
          style: TextStyle(
              fontSize: size * 0.36,
              fontWeight: FontWeight.w800,
              color: PistakColors.accent)),
    );
  }
}
