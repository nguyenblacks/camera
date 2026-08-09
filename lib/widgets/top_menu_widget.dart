import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/camera_settings.dart';
import '../theme/app_theme.dart';

class TopMenuWidget extends StatefulWidget {
  final CameraSettings settings;
  final ValueChanged<CameraSettings> onSettingsChanged;

  const TopMenuWidget({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
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
        // Flash icon + chevron row
        GestureDetector(
          onTap: () => setState(() => _menuOpen = !_menuOpen),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_flashIcon, color: _flashColor, size: 26),
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

        // Dropdown panel
        if (_menuOpen)
          Container(
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(210),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withAlpha(30), width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    ],
                    selected: widget.settings.aspectRatio,
                    onSelected: (v) => widget.onSettingsChanged(
                        widget.settings.copyWith(aspectRatio: v)),
                  ),
                ),
                _buildDivider(),
                _buildSection(
                  label: 'Frames',
                  child: _buildChipRow<BurstCount>(
                    items: const [
                      (BurstCount.frames30, '30'),
                      (BurstCount.frames100, '100'),
                      (BurstCount.frames300, '300'),
                    ],
                    selected: widget.settings.burstCount,
                    onSelected: (v) => widget.onSettingsChanged(
                        widget.settings.copyWith(burstCount: v)),
                  ),
                ),
                _buildDivider(),
                _buildSection(
                  label: 'Grid',
                  child: GestureDetector(
                    onTap: () => widget.onSettingsChanged(
                        widget.settings.copyWith(showGrid: !widget.settings.showGrid)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.settings.showGrid
                            ? Colors.white.withAlpha(230)
                            : Colors.white.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: Text(
                        widget.settings.showGrid ? 'On' : 'Off',
                        style: TextStyle(
                          color: widget.settings.showGrid
                              ? Colors.black
                              : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 180.ms).slideY(begin: -0.1, end: 0),
      ],
    );
  }

  Widget _buildSection({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
          child,
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: items.map((item) {
        final isSelected = item.$1 == selected;
        return GestureDetector(
          onTap: () => onSelected(item.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white.withAlpha(230) : Colors.white.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? Colors.transparent : Colors.white30,
                width: 0.8,
              ),
            ),
            child: Text(
              item.$2,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
