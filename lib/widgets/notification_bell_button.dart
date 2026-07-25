import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NotificationBellButton extends StatefulWidget {
  final int unreadCount;
  final VoidCallback onPressed;

  const NotificationBellButton({
    super.key,
    required this.unreadCount,
    required this.onPressed,
  });

  @override
  State<NotificationBellButton> createState() =>
      _NotificationBellButtonState();
}

class _NotificationBellButtonState
    extends State<NotificationBellButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _shakeTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _syncShakeTimer();
  }

  @override
  void didUpdateWidget(
    covariant NotificationBellButton oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.unreadCount != widget.unreadCount) {
      _syncShakeTimer();

      if (oldWidget.unreadCount == 0 && widget.unreadCount > 0) {
        _shakeOnce();
      }
    }
  }

  void _syncShakeTimer() {
    _shakeTimer?.cancel();

    if (widget.unreadCount <= 0) return;

    _shakeTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _shakeOnce(),
    );
  }

  Future<void> _shakeOnce() async {
    if (!mounted) return;
    if (widget.unreadCount <= 0) return;
    if (_controller.isAnimating) return;

    await _controller.forward(from: 0);
    if (!mounted) return;
    await _controller.reverse();
  }

  @override
  void dispose() {
    _shakeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = widget.unreadCount > 0;
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final angle = math.sin(_controller.value * math.pi * 6) * 0.20;

        return Transform.rotate(
          angle: angle,
          child: child,
        );
      },
      child: IconButton(
        tooltip: 'Notifications',
        onPressed: widget.onPressed,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.notifications_outlined,
                size: 20,
                color: colorScheme.primary,
              ),
            ),
            if (hasUnread)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}