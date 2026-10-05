import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds its child periodically with the current time.
///
/// It only REPAINTS: the displayed time is always recomputed from stored
/// timestamps, never accumulated here.
class TickerBuilder extends StatefulWidget {
  const TickerBuilder({
    super.key,
    required this.builder,
    this.interval = const Duration(milliseconds: 250),
  });

  final Widget Function(BuildContext context, DateTime now) builder;
  final Duration interval;

  @override
  State<TickerBuilder> createState() => _TickerBuilderState();
}

class _TickerBuilderState extends State<TickerBuilder> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, DateTime.now().toUtc());
}
