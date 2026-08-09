import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/camera_settings.dart';
import '../services/device_info_service.dart';
import '../services/sound_service.dart';

class CaptureSoundScreen extends StatefulWidget {
  final CameraSettings settings;
  final ValueChanged<CameraSettings> onSettingsChanged;

  const CaptureSoundScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<CaptureSoundScreen> createState() => _CaptureSoundScreenState();
}

class _CaptureSoundScreenState extends State<CaptureSoundScreen> {
  late CameraSettings _currentSettings;
  List<Map<String, String>> _ringtones = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.settings;
    _loadRingtones();
  }

  Future<void> _loadRingtones() async {
    final list = await DeviceInfoService.getNotificationRingtones();
    if (mounted) {
      setState(() {
        _ringtones = list;
        _loading = false;
      });
    }
  }

  void _updateSettings(CameraSettings newSettings) {
    setState(() => _currentSettings = newSettings);
    widget.onSettingsChanged(newSettings);
    HapticFeedback.selectionClick();
  }

  void _selectSound(String? path) {
    _updateSettings(_currentSettings.copyWith(selectedSoundPath: path));
    if (path == null) {
      SoundService.playShutterSound();
    } else {
      SoundService.playShutterSound(); // plays configured sound
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        title: const Text(
          'Capture Sound',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
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
          // Enable/disable shutter sound switch tile
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SwitchListTile(
              title: const Text(
                'Shutter Sound',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Play sound effect when capturing',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
              value: _currentSettings.enableShutterSound,
              activeThumbColor: Colors.amber,
              onChanged: (val) => _updateSettings(
                _currentSettings.copyWith(enableShutterSound: val),
              ),
            ),
          ),
          const SizedBox(height: 24),

          if (_currentSettings.enableShutterSound) ...[
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                'Select Sound Effect',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Built-in shutter sound option
            _buildSoundRow(
              title: 'Default Shutter',
              subtitle: 'Built-in camera shutter click',
              isSelected: _currentSettings.selectedSoundPath == null,
              onTap: () => _selectSound(null),
            ),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
                ),
              )
            else
              ..._ringtones.map((r) {
                final uri = r['uri']!;
                final title = r['title']!;
                final isSelected = _currentSettings.selectedSoundPath == uri;
                return _buildSoundRow(
                  title: title,
                  subtitle: 'System Notification Sound',
                  isSelected: isSelected,
                  onTap: () => _selectSound(uri),
                );
              }),
          ],
        ],
      ),
    );
  }

  Widget _buildSoundRow({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.amber.withAlpha(180) : Colors.transparent,
          width: 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.amber : Colors.white,
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle_rounded, color: Colors.amber, size: 22)
            : const Icon(Icons.volume_up_outlined, color: Colors.white38, size: 20),
      ),
    );
  }
}
