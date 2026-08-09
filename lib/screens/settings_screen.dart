import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/camera_settings.dart';

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
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        title: const Text(
          'Camera Settings',
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildHeader('GENERAL'),
          _buildSwitchTile(
            title: 'Shutter Sound',
            subtitle: 'Play sound effect when taking a photo',
            icon: Icons.volume_up_rounded,
            value: _currentSettings.enableShutterSound,
            onChanged: (val) => _update(
              _currentSettings.copyWith(enableShutterSound: val),
            ),
          ),
          _buildSwitchTile(
            title: 'Grid Lines',
            subtitle: 'Show 3x3 framing grid on preview',
            icon: Icons.grid_on_rounded,
            value: _currentSettings.showGrid,
            onChanged: (val) => _update(
              _currentSettings.copyWith(showGrid: val),
            ),
          ),

          const SizedBox(height: 24),
          _buildHeader('CAPTURE & RATIO'),
          _buildChoiceTile<AspectRatioMode>(
            title: 'Aspect Ratio',
            subtitle: 'Default frame size (4:3 recommended for 8MP)',
            icon: Icons.aspect_ratio_rounded,
            current: _currentSettings.aspectRatio,
            options: const [
              (AspectRatioMode.ratio4x3, '4:3 (Default)'),
              (AspectRatioMode.ratio16x9, '16:9'),
              (AspectRatioMode.ratio1x1, '1:1 Square'),
              (AspectRatioMode.full, 'Full Screen'),
            ],
            onSelected: (val) => _update(
              _currentSettings.copyWith(aspectRatio: val),
            ),
          ),
          _buildChoiceTile<PictureQuality>(
            title: 'Camera Picture Quality',
            subtitle: 'Choose capture mode & frame stacking depth',
            icon: Icons.high_quality_rounded,
            current: _currentSettings.quality,
            options: const [
              (PictureQuality.low, 'Low (1 Frame Instant)'),
              (PictureQuality.medium, 'Medium (10 Frames)'),
              (PictureQuality.high, 'High (20 Frames)'),
              (PictureQuality.veryHigh, 'Very High (50 Frames)'),
              (PictureQuality.ultraHigh, 'Ultra High (100 Frames)'),
            ],
            onSelected: (val) => _update(
              _currentSettings.copyWith(quality: val),
            ),
          ),

          const SizedBox(height: 24),
          _buildHeader('HARDWARE & FLICKER CONTROL'),
          _buildChoiceTile<AntiBandingMode>(
            title: 'Anti-Banding (Flicker Control)',
            subtitle: 'Prevent artificial light banding (50Hz / 60Hz)',
            icon: Icons.wb_incandescent_rounded,
            current: _currentSettings.antiBanding,
            options: const [
              (AntiBandingMode.auto, 'Auto (Recommended)'),
              (AntiBandingMode.hz50, '50 Hz (Europe/Asia)'),
              (AntiBandingMode.hz60, '60 Hz (Americas)'),
              (AntiBandingMode.off, 'Off'),
            ],
            onSelected: (val) => _update(
              _currentSettings.copyWith(antiBanding: val),
            ),
          ),
          _buildChoiceTile<FlashMode>(
            title: 'Flash Mode',
            subtitle: 'Default flash behavior',
            icon: Icons.flash_on_rounded,
            current: _currentSettings.flashMode,
            options: const [
              (FlashMode.off, 'Off'),
              (FlashMode.auto, 'Auto'),
              (FlashMode.always, 'On'),
              (FlashMode.torch, 'Torch (Constant Light)'),
            ],
            onSelected: (val) => _update(
              _currentSettings.copyWith(flashMode: val),
            ),
          ),

          const SizedBox(height: 24),
          _buildHeader('ABOUT HARDWARE ENGINE'),
          _buildInfoTile(
            title: 'MediaTek Imagiq ISP Engine',
            subtitle: 'Enabled (Hardware MFNR + Super Clarity Warmth tuning)',
            icon: Icons.memory_rounded,
          ),
          _buildInfoTile(
            title: 'Storage Album',
            subtitle: 'Pictures saved to Gallery / Swavoti Camera',
            icon: Icons.folder_special_rounded,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SwitchListTile(
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
      ),
    );
  }

  Widget _buildChoiceTile<T>({
    required String title,
    required String subtitle,
    required IconData icon,
    required T current,
    required List<(T, String)> options,
    required ValueChanged<T> onSelected,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((opt) {
              final isSel = opt.$1 == current;
              return ChoiceChip(
                label: Text(
                  opt.$2,
                  style: TextStyle(
                    color: isSel ? Colors.black : Colors.white70,
                    fontSize: 12,
                    fontWeight: isSel ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
                selected: isSel,
                selectedColor: Colors.amber,
                backgroundColor: const Color(0xFF2B2B2B),
                onSelected: (_) => onSelected(opt.$1),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
