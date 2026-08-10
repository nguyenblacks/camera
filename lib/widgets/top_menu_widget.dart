import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/camera_settings.dart';
import '../theme/app_theme.dart';

class TopMenuWidget extends StatefulWidget {
  final CameraSettings settings;
  final ValueChanged<CameraSettings> onSettingsChanged;
  final VoidCallback? onOpenSettings;
  final String videoCapsText;
  final VoidCallback? onToggleVideoQuality;

  const TopMenuWidget({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    this.onOpenSettings,
    this.videoCapsText = '',
    this.onToggleVideoQuality,
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

  bool get _isHdrActive {
    return widget.settings.hdrMode == HdrMode.on ||
        widget.settings.hdrMode == HdrMode.auto;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top bar row: Flash + Dropdown (left) | HDR Pill (center) | Settings / Video Specs (right)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left: Flash toggle dropdown trigger
            GestureDetector(
              onTap: () => setState(() => _menuOpen = !_menuOpen),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

            // Center: HDR Mode text button
            if (widget.settings.cameraMode != CameraMode.video)
              GestureDetector(
              onTap: () {
                final next = widget.settings.hdrMode == HdrMode.auto
                    ? HdrMode.on
                    : (widget.settings.hdrMode == HdrMode.on
                        ? HdrMode.off
                        : HdrMode.auto);
                widget.onSettingsChanged(widget.settings.copyWith(hdrMode: next));
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Text(
                  widget.settings.hdrLabel.toUpperCase(),
                  style: TextStyle(
                    color: _isHdrActive ? Colors.amber : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),

            // Right: Video Caps Badge (in Video mode) + Settings gear
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.settings.cameraMode == CameraMode.video &&
                    widget.videoCapsText.isNotEmpty)
                  GestureDetector(
                    onTap: widget.onToggleVideoQuality,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4, left: 10, top: 6, bottom: 6),
                      child: Text(
                        widget.videoCapsText,
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                if (widget.onOpenSettings != null)
                  GestureDetector(
                    onTap: widget.onOpenSettings,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: const Icon(
                        Icons.settings_outlined,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),

        // Solid dark quick settings panel with clean inline option rows
        if (_menuOpen)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A), // Solid dark background
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12, width: 1.0),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black87,
                  blurRadius: 16,
                  offset: Offset(0, 4),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInlineRow(
                  label: 'Flash',
                  child: _buildChipRow<FlashMode>(
                    items: widget.settings.cameraMode == CameraMode.video 
                        ? const [
                            (FlashMode.off, 'Off'),
                            (FlashMode.torch, 'Torch'),
                          ]
                        : const [
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
                if (widget.settings.cameraMode != CameraMode.video) ...[
                  _buildDivider(),
                  _buildInlineRow(
                    label: 'HDR',
                    child: _buildChipRow<HdrMode>(
                      items: const [
                        (HdrMode.auto, 'Auto'),
                        (HdrMode.on, 'On'),
                        (HdrMode.off, 'Off'),
                      ],
                      selected: widget.settings.hdrMode,
                      onSelected: (v) => widget.onSettingsChanged(
                          widget.settings.copyWith(hdrMode: v)),
                    ),
                  ),
                  _buildDivider(),
                  _buildInlineRow(
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
                ],
                _buildDivider(),
                _buildInlineRow(
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
                _buildInlineRow(
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

  Widget _buildInlineRow({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildDivider() => const Divider(
        height: 1,
        thickness: 0.5,
        indent: 14,
        endIndent: 14,
        color: Colors.white10,
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
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? Colors.amber : const Color(0xFF282828),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? Colors.amber : Colors.white12,
                  width: 0.8,
                ),
              ),
              child: Text(
                item.$2,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
