import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Zoom control widget for rear camera.
///
/// Shows 1x / 2x buttons (and 0.5x if ultrawide is available).
/// When 2x is selected, an arc slider appears for fine-grained zoom
/// from 1x up to the sensor's max zoom.
class ZoomControlWidget extends StatefulWidget {
  final double currentZoom;
  final double minZoom;
  final double maxZoom;
  final bool hasUltraWide;
  final ValueChanged<double> onZoomChanged;

  const ZoomControlWidget({
    super.key,
    required this.currentZoom,
    required this.minZoom,
    required this.maxZoom,
    this.hasUltraWide = false,
    required this.onZoomChanged,
  });

  @override
  State<ZoomControlWidget> createState() => _ZoomControlWidgetState();
}

class _ZoomControlWidgetState extends State<ZoomControlWidget>
    with SingleTickerProviderStateMixin {
  bool _showArcSlider = false;
  late AnimationController _arcAnimController;
  late Animation<double> _arcAnim;

  @override
  void initState() {
    super.initState();
    _arcAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _arcAnim = CurvedAnimation(
      parent: _arcAnimController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _arcAnimController.dispose();
    super.dispose();
  }

  void _toggleArcSlider(bool show) {
    setState(() => _showArcSlider = show);
    if (show) {
      _arcAnimController.forward();
    } else {
      _arcAnimController.reverse();
    }
  }

  String get _zoomLabel {
    if (widget.currentZoom < 1.0) {
      return '${widget.currentZoom.toStringAsFixed(1)}x';
    }
    if (widget.currentZoom == widget.currentZoom.roundToDouble()) {
      return '${widget.currentZoom.round()}x';
    }
    return '${widget.currentZoom.toStringAsFixed(1)}x';
  }

  @override
  Widget build(BuildContext context) {
    // Determine which preset buttons to show
    final List<double> presets = [];
    if (widget.hasUltraWide && widget.minZoom < 1.0) {
      presets.add(widget.minZoom.clamp(0.5, 1.0));
    }
    presets.add(1.0);
    if (widget.maxZoom >= 2.0) {
      presets.add(2.0);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Arc slider (shown when user taps 2x or drags)
        AnimatedBuilder(
          animation: _arcAnim,
          builder: (context, child) {
            if (_arcAnim.value < 0.01) return const SizedBox.shrink();
            return Opacity(
              opacity: _arcAnim.value,
              child: Transform.scale(
                scale: 0.8 + 0.2 * _arcAnim.value,
                child: _buildArcSlider(),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        // Preset zoom pills
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(140),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: presets.map((z) => _buildPresetPill(z)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetPill(double zoom) {
    final isActive = (widget.currentZoom - zoom).abs() < 0.05 ||
        (zoom == 2.0 && widget.currentZoom >= 2.0);
    final label = zoom < 1.0
        ? '${zoom.toStringAsFixed(1)}x'
        : '${zoom.round()}x';

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onZoomChanged(zoom);
        if (zoom >= 2.0 && !_showArcSlider) {
          _toggleArcSlider(true);
        } else if (zoom < 2.0 && _showArcSlider) {
          _toggleArcSlider(false);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive
              ? Colors.amber.withAlpha(230)
              : Colors.white.withAlpha(25),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildArcSlider() {
    // Half-ring arc from 2x to maxZoom
    final effectiveMax = widget.maxZoom.clamp(2.0, 10.0);

    return SizedBox(
      width: 180,
      height: 90,
      child: GestureDetector(
        onPanUpdate: (details) {
          // Map horizontal drag to zoom
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final localPos = box.globalToLocal(details.globalPosition);
          // Map x position across the arc width (0..180) to zoom range
          final fraction = (localPos.dx / 180.0).clamp(0.0, 1.0);
          final newZoom = 2.0 + fraction * (effectiveMax - 2.0);
          widget.onZoomChanged(double.parse(newZoom.toStringAsFixed(1)));
          HapticFeedback.selectionClick();
        },
        onPanEnd: (_) {
          // Keep arc visible
        },
        child: CustomPaint(
          painter: _ArcSliderPainter(
            currentZoom: widget.currentZoom,
            minZoom: 2.0,
            maxZoom: effectiveMax,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _zoomLabel,
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcSliderPainter extends CustomPainter {
  final double currentZoom;
  final double minZoom;
  final double maxZoom;

  _ArcSliderPainter({
    required this.currentZoom,
    required this.minZoom,
    required this.maxZoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height + 10);
    final radius = size.width / 2 - 8;

    // Background arc
    final bgPaint = Paint()
      ..color = Colors.white.withAlpha(30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    const startAngle = pi + 0.3; // Just past left
    const sweepAngle = pi - 0.6; // Half circle with margins

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Active arc
    final fraction =
        ((currentZoom - minZoom) / (maxZoom - minZoom)).clamp(0.0, 1.0);
    final activeSweep = sweepAngle * fraction;

    final activePaint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      activeSweep,
      false,
      activePaint,
    );

    // Thumb dot
    final thumbAngle = startAngle + activeSweep;
    final thumbX = center.dx + radius * cos(thumbAngle);
    final thumbY = center.dy + radius * sin(thumbAngle);

    canvas.drawCircle(
      Offset(thumbX, thumbY),
      7,
      Paint()..color = Colors.amber,
    );
    canvas.drawCircle(
      Offset(thumbX, thumbY),
      4,
      Paint()..color = Colors.black87,
    );

    // Tick marks
    final tickPaint = Paint()
      ..color = Colors.white.withAlpha(60)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      final t = i / 4.0;
      final angle = startAngle + sweepAngle * t;
      final innerR = radius - 6;
      final outerR = radius + 6;
      canvas.drawLine(
        Offset(center.dx + innerR * cos(angle), center.dy + innerR * sin(angle)),
        Offset(center.dx + outerR * cos(angle), center.dy + outerR * sin(angle)),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArcSliderPainter oldDelegate) =>
      oldDelegate.currentZoom != currentZoom;
}
