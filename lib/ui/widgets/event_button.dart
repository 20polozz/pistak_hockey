import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Big one-tap recording button: colour + icon + text (never colour only).
class EventButton extends StatelessWidget {
  const EventButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
    this.sublabel,
    this.filled = false,
  });

  final String label;
  final String? sublabel;
  final IconData? icon;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.black : Colors.white;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: filled ? fg : color, size: 22),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              if (sublabel != null)
                Text(
                  sublabel!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: filled ? color : PistakColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: color.withValues(alpha: 0.35),
          highlightColor: color.withValues(alpha: 0.2),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              // The grid must fit one screen during a match: labels follow
              // the system text size up to 1.3× (they're already big/bold),
              // wrap within the button width and, if still too tall for the
              // cell, scale down instead of being cut off.
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: LayoutBuilder(
                  builder: (context, box) => Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: box.maxWidth.isFinite
                                ? box.maxWidth
                                : double.infinity),
                        child: content,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Card button: just the card, in its colour (the name is only for screen
/// readers). Same size and touch area as [EventButton].
class CardButton extends StatelessWidget {
  const CardButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: PistakColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withValues(alpha: 0.6), width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashColor: color.withValues(alpha: 0.35),
            highlightColor: color.withValues(alpha: 0.2),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: LayoutBuilder(builder: (context, box) {
                // A real card is ~2:3; fill most of the button height.
                final h = (box.maxHeight.isFinite ? box.maxHeight : 56) * 0.66;
                final cardH = h.clamp(30.0, 64.0);
                return Center(
                  child: Transform.rotate(
                    angle: -0.12,
                    child: Container(
                      width: cardH * 0.7,
                      height: cardH,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(cardH * 0.1),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black54,
                              blurRadius: 6,
                              offset: Offset(2, 3)),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small card shape (2:3) in a card colour, for titles and chips.
class MiniCard extends StatelessWidget {
  const MiniCard({super.key, required this.color, this.height = 22});
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        width: height * 0.7,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height * 0.12),
        ),
      );
}

/// Soft pulsing glow around [child] (e.g. RESUME while the clock is
/// stopped) so it can't go unnoticed. No animation when not [active].
class PulsingGlow extends StatefulWidget {
  const PulsingGlow(
      {super.key,
      required this.child,
      required this.color,
      this.active = true});
  final Widget child;
  final Color color;
  final bool active;

  @override
  State<PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<PulsingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PulsingGlow old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.active && !reduce) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = widget.active ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.25 + 0.45 * t),
                blurRadius: 6 + 16 * t,
                spreadRadius: 1 + 3 * t,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}
