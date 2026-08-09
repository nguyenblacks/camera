import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

class PreviewScreen extends StatelessWidget {
  final Uint8List imageBytes;

  const PreviewScreen({super.key, required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withAlpha(100),
            ),
            child: const Icon(Icons.arrow_back_rounded,
                color: Colors.white, size: 22),
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () async {
              await HapticFeedback.lightImpact();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Share coming soon'),
                  backgroundColor: Color(0xFF222222),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },

            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withAlpha(100),
              ),
              child: const Icon(Icons.share_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
      body: InteractiveViewer(
        minScale: 0.8,
        maxScale: 6.0,
        child: Center(
          child: Image.memory(
            imageBytes,
            fit: BoxFit.contain,
          )
              .animate()
              .fadeIn(duration: 300.ms)
              .scale(begin: const Offset(0.97, 0.97), end: const Offset(1, 1)),
        ),
      ),
    );
  }
}
