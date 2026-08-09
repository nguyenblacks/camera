import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ShutterButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isProcessing;
  final bool isVideoMode;
  final bool isRecording;

  const ShutterButton({
    super.key,
    required this.onPressed,
    this.isProcessing = false,
    this.isVideoMode = false,
    this.isRecording = false,
  });

  @override
  State<ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<ShutterButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnim;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.isProcessing || widget.onPressed == null) return;
    setState(() => _isPressed = true);
    _pressController.forward();
    HapticFeedback.mediumImpact();
  }

  void _onTapUp(TapUpDetails _) {
    _release();
    widget.onPressed?.call();
  }

  void _onTapCancel() => _release();

  void _release() {
    setState(() => _isPressed = false);
    _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final Color buttonColor = widget.isVideoMode
        ? (widget.isRecording ? Colors.red : Colors.redAccent)
        : (widget.isProcessing ? Colors.white.withAlpha(100) : Colors.white);

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnim.value,
            child: child,
          );
        },
        child: SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer ring
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.isRecording
                        ? Colors.red.withAlpha(200)
                        : Colors.white.withAlpha(200),
                    width: 3,
                  ),
                ),
              ),
              // Inner filled shape (circle in photo/idle, rounded square when recording)
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: widget.isRecording ? 32 : (_isPressed ? 60 : 66),
                height: widget.isRecording ? 32 : (_isPressed ? 60 : 66),
                decoration: BoxDecoration(
                  borderRadius: widget.isRecording
                      ? BorderRadius.circular(8)
                      : BorderRadius.circular(40),
                  color: buttonColor,
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate(target: widget.isProcessing ? 1.0 : 0.0).fade(
          begin: 1.0,
          end: 0.5,
          duration: 300.ms,
        );
  }
}
