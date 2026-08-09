import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/camera_settings.dart';
import 'capture_sound_screen.dart';

class SettingsScreen extends StatefulWidget {
  final CameraSettings settings;
  final ValueChanged<CameraSettings> onSettingsChanged;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late CameraSettings _currentSettings;

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.settings;
  }

  void _update(CameraSettings newSettings) {
    setState(() => _currentSettings = newSettings);
    widget.onSettingsChanged(newSettings);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0C0C),
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildSectionHeader('General'),
          _buildActionRow(
            title: 'Capture sound',
            valueText: _currentSettings.enableShutterSound
                ? (_currentSettings.selectedSoundPath == null ? 'Default' : 'Custom')
                : 'Off',
            icon: Icons.volume_up_outlined,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CaptureSoundScreen(
                    settings: _currentSettings,
                    onSettingsChanged: _update,
                  ),
                ),
              );
            },
          ),
          _buildDivider(),
          _buildSwitchRow(
            title: 'Grid lines',
            subtitle: '3x3 framing grid overlay',
            icon: Icons.grid_on_outlined,
            value: _currentSettings.showGrid,
            onChanged: (val) => _update(_currentSettings.copyWith(showGrid: val)),
          ),
          _buildDivider(),
          _buildSwitchRow(
            title: 'Device watermark',
            subtitle: 'Add model name and timestamp to photo',
            icon: Icons.branding_watermark_outlined,
            value: _currentSettings.watermarkEnabled,
            onChanged: (val) =>
                _update(_currentSettings.copyWith(watermarkEnabled: val)),
          ),
          _buildDivider(),
          _buildSwitchRow(
            title: 'Save location info',
            subtitle: 'Embed GPS coordinates into saved photos',
            icon: Icons.location_on_outlined,
            value: _currentSettings.saveLocationInfo,
            onChanged: (val) =>
                _update(_currentSettings.copyWith(saveLocationInfo: val)),
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('Photo & capture'),
          _buildActionRow(
            title: 'Picture quality',
            valueText: _currentSettings.qualityShortLabel,
            icon: Icons.high_quality_outlined,
            onTap: () => _showModalPicker<PictureQuality>(
              title: 'Picture Quality',
              current: _currentSettings.quality,
              options: const [
                (PictureQuality.low, 'Low', '1 shot, instant capture'),
                (PictureQuality.medium, 'Standard', '2-shot blend (recommended)'),
                (PictureQuality.high, 'High', '2-shot + sharpness boost'),
                (PictureQuality.veryHigh, 'Very High', '2-shot + multi-pass enhancement'),
                (PictureQuality.ultraHigh, 'Ultra', '2-shot + maximum clarity'),
              ],
              onSelected: (val) => _update(_currentSettings.copyWith(quality: val)),
            ),
          ),
          _buildDivider(),
          _buildActionRow(
            title: 'Aspect ratio',
            valueText: _currentSettings.aspectLabel,
            icon: Icons.aspect_ratio_outlined,
            onTap: () => _showModalPicker<AspectRatioMode>(
              title: 'Aspect Ratio',
              current: _currentSettings.aspectRatio,
              options: const [
                (AspectRatioMode.ratio4x3, '4:3', 'Default sensor aspect ratio'),
                (AspectRatioMode.ratio16x9, '16:9', 'Widescreen format'),
                (AspectRatioMode.ratio1x1, '1:1', 'Square crop'),
                (AspectRatioMode.full, 'Full screen', 'Matches device screen'),
              ],
              onSelected: (val) =>
                  _update(_currentSettings.copyWith(aspectRatio: val)),
            ),
          ),
          _buildDivider(),
          _buildActionRow(
            title: 'Timer delay',
            valueText: _currentSettings.timerLabel,
            icon: Icons.timer_outlined,
            onTap: () => _showModalPicker<TimerDelay>(
              title: 'Timer Delay',
              current: _currentSettings.timerDelay,
              options: const [
                (TimerDelay.off, 'Off', 'Instant shutter'),
                (TimerDelay.three, '3 seconds', '3s countdown before capture'),
                (TimerDelay.ten, '10 seconds', '10s countdown before capture'),
              ],
              onSelected: (val) =>
                  _update(_currentSettings.copyWith(timerDelay: val)),
            ),
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('Hardware & flicker'),
          _buildActionRow(
            title: 'Anti-banding (Flicker control)',
            valueText: _currentSettings.antiBandingLabel,
            icon: Icons.wb_incandescent_outlined,
            onTap: () => _showModalPicker<AntiBandingMode>(
              title: 'Anti-Banding',
              current: _currentSettings.antiBanding,
              options: const [
                (AntiBandingMode.auto, 'Auto', 'Recommended for most environments'),
                (AntiBandingMode.hz50, '50 Hz', 'Europe, Asia, Africa'),
                (AntiBandingMode.hz60, '60 Hz', 'Americas, Japan'),
                (AntiBandingMode.off, 'Off', 'Disable anti-banding filter'),
              ],
              onSelected: (val) =>
                  _update(_currentSettings.copyWith(antiBanding: val)),
            ),
          ),
          _buildDivider(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.amber,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildActionRow({
    required String title,
    required String valueText,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, color: Colors.white70, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            valueText,
            style: const TextStyle(color: Colors.white38, fontSize: 14),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
        ],
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      secondary: Icon(icon, color: Colors.white70, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      value: value,
      activeThumbColor: Colors.amber,
      onChanged: onChanged,
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      thickness: 0.5,
      indent: 54,
      endIndent: 16,
      color: Colors.white10,
    );
  }

  void _showModalPicker<T>({
    required String title,
    required T current,
    required List<(T, String, String)> options,
    required ValueChanged<T> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: options.map((opt) {
                      final isSel = opt.$1 == current;
                      return ListTile(
                        onTap: () {
                          onSelected(opt.$1);
                          Navigator.pop(ctx);
                        },
                        title: Text(
                          opt.$2,
                          style: TextStyle(
                            color: isSel ? Colors.amber : Colors.white,
                            fontSize: 15,
                            fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          opt.$3,
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        trailing: isSel
                            ? const Icon(Icons.radio_button_checked_rounded,
                                color: Colors.amber, size: 20)
                            : const Icon(Icons.radio_button_unchecked_rounded,
                                color: Colors.white38, size: 20),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
