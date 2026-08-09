import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/camera_settings.dart';
import '../theme/app_theme.dart';

class TopMenuWidget extends StatefulWidget {
  final CameraSettings settings;
  final ValueChanged<CameraSettings> onSettingsChanged;
  final VoidCallback? onOpenSettings;

  const TopMenuWidget({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    this.onOpenSettings,
  });

  @override
  State<TopMenuWidget> createState() => _TopMenuWidgetState();
}

class _TopMenuWidgetState extends State<TopMenuWidget> {
  bool _menuOpen = false;

  IconData get _flashIcon {
    switch (widget.settings.flashMode) {
      case FlashMode.off:
        return Icons.flash_off_rounded;
      case FlashMode.auto:
        return Icons.flash_auto_rounded;
      case FlashMode.always:
        return Icons.flash_on_rounded;
      case FlashMode.torch:
        return Icons.highlight_rounded;
    }
  }

  Color get _flashColor {
    if (widget.settings.flashMode == FlashMode.off) return Colors.white54;
    return AppTheme.accent;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top bar row: Flash icon + chevron (left) AND Settings gear (right)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () => setState(() => _menuOpen = !_menuOpen),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_flashIcon, color: _flashColor, size: 24),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _menuOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.onOpenSettings != null)
              GestureDetector(
                onTap: widget.onOpenSettings,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: const Icon(
                    Icons.settings_outlined,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
          ],
        ),

        // Quick dropdown panel
        if (_menuOpen)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(220),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withAlpha(30), width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSection(
                  label: 'Flash',
                  child: _buildChipRow<FlashMode>(
                    items: const [
                      (FlashMode.off, 'Off'),
                      (FlashMode.auto, 'Auto'),
                      (FlashMode.always, 'On'),
                      (FlashMode.torch, 'Torch'),
                    ],
                    selected: widget.settings.flashMode,
                    onSelected: (v) => widget.onSettingsChanged(
                        widget.settings.copyWith(flashMode: v)),
                  ),
                ),
                _buildDivider(),
                _buildSection(
                  label: 'Timer',
                  child: _buildChipRow<TimerDelay>(
                    items: const [
                      (TimerDelay.off, 'Off'),
                      (TimerDelay.three, '3s'),
                      (TimerDelay.ten, '10s'),
                    ],
                    selected: widget.settings.timerDelay,
                    onSelected: (v) => widget.onSettingsChanged(
                        widget.settings.copyWith(timerDelay: v)),
                  ),
                ),
                _buildDivider(),
                _buildSection(
                  label: 'Ratio',
                  child: _buildChipRow<AspectRatioMode>(
                    items: const [
                      (AspectRatioMode.ratio4x3, '4:3'),
                      (AspectRatioMode.ratio16x9, '16:9'),
                      (AspectRatioMode.ratio1x1, '1:1'),
                      (AspectRatioMode.full, 'Full'),
                    ],
                    selected: widget.settings.aspectRatio,
                    onSelected: (v) => widget.onSettingsChanged(
                        widget.settings.copyWith(aspectRatio: v)),
                  ),
                ),
                _buildDivider(),
                _buildSection(
                  label: 'Quality',
                  child: _buildChipRow<PictureQuality>(
                    items: const [
                      (PictureQuality.low, 'Low'),
                      (PictureQuality.medium, 'Standard'),
                      (PictureQuality.high, 'High'),
                      (PictureQuality.veryHigh, 'V.High'),
                      (PictureQuality.ultraHigh, 'Ultra'),
                    ],
                    selected: widget.settings.quality,
                    onSelected: (v) => widget.onSettingsChanged(
                        widget.settings.copyWith(quality: v)),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 180.ms).slideY(begin: -0.05, end: 0),
      ],
    );
  }

  Widget _buildSection({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildDivider() => Container(
        height: 0.5,
        color: Colors.white.withAlpha(25),
        margin: const EdgeInsets.symmetric(horizontal: 16),
      );

  Widget _buildChipRow<T>({
    required List<(T, String)> items,
    required T selected,
    required ValueChanged<T> onSelected,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.map((item) {
          final isSelected = item.$1 == selected;
          return GestureDetector(
            onTap: () => onSelected(item.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? Colors.amber : Colors.white.withAlpha(18),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? Colors.amber : Colors.white24,
                  width: 0.8,
                ),
              ),
              child: Text(
                item.$2,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
