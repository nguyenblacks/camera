import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

enum ThumbnailState { idle, processing, done }

class ThumbnailWidget extends StatelessWidget {
  final Uint8List? imageBytes;
  final ThumbnailState state;
  final VoidCallback? onTap;

  const ThumbnailWidget({
    super.key,
    this.imageBytes,
    this.state = ThumbnailState.idle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: imageBytes != null ? onTap : null,
      child: SizedBox(
        width: 56,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background / image
              _buildBackground(),

              // Spinner overlay during processing
              if (state == ThumbnailState.processing)
                _buildSpinnerOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackground() {
    if (imageBytes == null) {
      // Empty slot — show a dashed rounded square
      return Container(
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.white.withAlpha(60),
            width: 1.5,
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: Image.memory(
        imageBytes!,
        key: ValueKey(imageBytes!.hashCode),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }

  Widget _buildSpinnerOverlay() {
    return Container(
      color: Colors.black.withAlpha(60),
      child: Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            backgroundColor: Colors.white.withAlpha(40),
          ),
        ),
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(
          duration: 1500.ms,
          color: Colors.white.withAlpha(30),
        );
  }
}
