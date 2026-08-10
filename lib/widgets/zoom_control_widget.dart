import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Modern iOS-style zoom control widget for rear camera.
///
/// Shows discrete lens buttons (e.g. 0.5, 1, 2, 5) in a horizontal pill.
/// The active lens button expands and displays the exact continuous zoom level.
/// Users can tap to switch lenses or drag horizontally to slide zoom smoothly.
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

class _ZoomControlWidgetState extends State<ZoomControlWidget> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    // Determine which preset lenses to show based on hardware capabilities
    final List<double> presets = [];
    
    // 1. Min zoom (e.g., ultrawide)
    if (widget.minZoom < 1.0) {
      presets.add(double.parse(widget.minZoom.toStringAsFixed(1)));
    }
    
    // 2. Base zoom
    presets.add(1.0);
    
    // 3. Intermediate presets
    if (widget.maxZoom >= 2.5) {
      presets.add(2.0);
    }
    if (widget.maxZoom >= 6.0) {
      presets.add(5.0);
    }
    
    // 4. Max zoom (the absolute limit of the lens)
    final roundedMax = double.parse(widget.maxZoom.toStringAsFixed(1));
    if (roundedMax > presets.last + 0.3) {
      presets.add(roundedMax);
    }

    // Determine the active lens (the largest preset that is <= currentZoom)
    double activePreset = presets.first;
    for (final p in presets.reversed) {
      if (widget.currentZoom >= p - 0.05) {
        activePreset = p;
        break;
      }
    }

    return GestureDetector(
      onHorizontalDragStart: (_) {
        setState(() => _isDragging = true);
        HapticFeedback.selectionClick();
      },
      onHorizontalDragUpdate: (details) {
        // Map horizontal drag to smooth zoom change
        final sensitivity = (widget.maxZoom - widget.minZoom) / 200.0;
        double newZoom = widget.currentZoom + (details.primaryDelta ?? 0) * sensitivity;
        newZoom = newZoom.clamp(widget.minZoom, widget.maxZoom);
        
        // Slight magnetic snap to exact presets
        for (final p in presets) {
          if ((newZoom - p).abs() < 0.1) {
            newZoom = p;
            break;
          }
        }
        widget.onZoomChanged(double.parse(newZoom.toStringAsFixed(1)));
      },
      onHorizontalDragEnd: (_) {
        setState(() => _isDragging = false);
        HapticFeedback.lightImpact();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _isDragging ? Colors.black.withAlpha(180) : Colors.black.withAlpha(140),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.white24, width: 0.5),
          boxShadow: _isDragging 
              ? [BoxShadow(color: Colors.black45, blurRadius: 10, spreadRadius: 2)] 
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: presets.map((z) => _buildPresetPill(z, activePreset)).toList(),
        ),
      ),
    );
  }

  Widget _buildPresetPill(double lensZoom, double activePreset) {
    final isActive = lensZoom == activePreset;
    
    // The active pill shows the precise current zoom, inactive ones show their base lens zoom
    String label;
    if (isActive) {
      label = widget.currentZoom < 1.0 
        ? widget.currentZoom.toStringAsFixed(1)
        : (widget.currentZoom == widget.currentZoom.roundToDouble()
            ? widget.currentZoom.round().toString()
            : widget.currentZoom.toStringAsFixed(1));
    } else {
      label = lensZoom < 1.0 ? lensZoom.toStringAsFixed(1) : lensZoom.round().toString();
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onZoomChanged(lensZoom);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        width: isActive ? 44 : 36,
        height: isActive ? 44 : 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? Colors.amber : Colors.black45,
          border: isActive ? null : Border.all(color: Colors.white30, width: 0.5),
          boxShadow: isActive ? [
            BoxShadow(color: Colors.amber.withAlpha(60), blurRadius: 8, spreadRadius: 2)
          ] : null,
        ),
        child: Text(
          isActive ? '${label}x' : label,
          style: TextStyle(
            color: isActive ? Colors.black : Colors.white,
            fontSize: isActive ? 13 : 12,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
