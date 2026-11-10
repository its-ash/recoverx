import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

/// Radar sweep shown while a scan runs. A blip lights up under the sweep
/// line each time new files are found. Freezes while [paused] and when the
/// system asks for reduced motion.
class ScanRadar extends StatefulWidget {
  const ScanRadar({
    super.key,
    required this.found,
    this.paused = false,
    this.indexing = false,
    this.size = 168,
  });

  /// Items found so far. An increase spawns blips.
  final int found;
  final bool paused;

  /// Indexing has no blips yet; the sweep runs slower.
  final bool indexing;
  final double size;

  @override
  State<ScanRadar> createState() => _ScanRadarState();
}

class _Blip {
  _Blip(this.angle, this.radius, this.born);

  final double angle;
  final double radius;
  final Duration born;
}

class _ScanRadarState extends State<ScanRadar> with SingleTickerProviderStateMixin {
  static const _blipLife = Duration(milliseconds: 1800);
  static const _maxBlips = 24;

  late final AnimationController _sweep = AnimationController(vsync: this, duration: _period);
  final _clock = Stopwatch()..start();
  final _blips = <_Blip>[];
  final _random = math.Random();

  Duration get _period => Duration(milliseconds: widget.indexing ? 3600 : 2200);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRunning();
  }

  @override
  void didUpdateWidget(ScanRadar old) {
    super.didUpdateWidget(old);
    if (old.indexing != widget.indexing) _sweep.duration = _period;
    final added = widget.found - old.found;
    if (added > 0 && _animate) {
      final angle = _sweep.value * 2 * math.pi;
      for (var i = 0; i < math.min(added, 3); i++) {
        _blips.add(_Blip(
          angle - _random.nextDouble() * 0.35,
          0.22 + _random.nextDouble() * 0.7,
          _clock.elapsed,
        ));
      }
      if (_blips.length > _maxBlips) _blips.removeRange(0, _blips.length - _maxBlips);
    }
    _syncRunning();
  }

  bool get _animate => !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _syncRunning() {
    final run = _animate && !widget.paused;
    if (run && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!run && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: widget.paused ? 'Scan paused' : 'Scanning',
      child: SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _sweep,
            builder: (context, _) {
              final now = _clock.elapsed;
              _blips.removeWhere((b) => now - b.born > _blipLife);
              return CustomPaint(
                painter: _RadarPainter(
                  sweep: _sweep.value,
                  blips: _blips,
                  now: now,
                  life: _blipLife,
                  accent: widget.paused ? colors.textSubtle : colors.accent,
                  ring: colors.border,
                  surface: colors.surfaceMuted,
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: context.motion(UiMotion.normal),
                    child: Icon(
                      widget.paused ? Icons.pause_rounded : Icons.radar_rounded,
                      key: ValueKey(widget.paused),
                      size: widget.size * 0.16,
                      color: widget.paused ? colors.textMuted : colors.accent,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.sweep,
    required this.blips,
    required this.now,
    required this.life,
    required this.accent,
    required this.ring,
    required this.surface,
  });

  final double sweep;
  final List<_Blip> blips;
  final Duration now;
  final Duration life;
  final Color accent;
  final Color ring;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Disc with a soft accent glow towards the edge.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [surface, Color.lerp(surface, accent, 0.10)!])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Rings and cross hairs.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ring;
    for (final f in const [0.33, 0.66, 1.0]) {
      canvas.drawCircle(c, r * f - 0.5, ringPaint);
    }
    canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), ringPaint);
    canvas.drawLine(c - Offset(0, r), c + Offset(0, r), ringPaint);

    // Sweep: a fading wedge trailing the leading line.
    final angle = sweep * 2 * math.pi;
    const trail = math.pi / 2.2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle - trail);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawArc(
      rect,
      0,
      trail,
      true,
      Paint()
        ..shader = SweepGradient(
          endAngle: trail,
          colors: [accent.withValues(alpha: 0), accent.withValues(alpha: 0.38)],
        ).createShader(rect),
    );
    canvas.restore();
    canvas.drawLine(
      c,
      c + Offset(math.cos(angle), math.sin(angle)) * r,
      Paint()
        ..color = accent
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Blips: pop in, then fade with an expanding ring.
    for (final b in blips) {
      final t = ((now - b.born).inMicroseconds / life.inMicroseconds).clamp(0.0, 1.0);
      final p = c + Offset(math.cos(b.angle), math.sin(b.angle)) * (r * b.radius);
      final fade = 1 - t;
      canvas.drawCircle(p, 3.5 + 1.5 * Curves.easeOutBack.transform(math.min(1, t * 4)),
          Paint()..color = accent.withValues(alpha: fade));
      canvas.drawCircle(
        p,
        4 + 14 * Curves.easeOut.transform(t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = accent.withValues(alpha: 0.5 * fade),
      );
    }

    // Outer rim.
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) => true;
}
