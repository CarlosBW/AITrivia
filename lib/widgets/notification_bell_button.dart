import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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
            Icon(
              Icons.notifications_rounded,
              size: 30,
              color: hasUnread ? Colors.amber.shade700 : Colors.black87,
            ),
            if (hasUnread)
              Positioned(
                right: -8,
                top: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 1.4,
                    ),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    widget.unreadCount > 99
                        ? '99+'
                        : '${widget.unreadCount}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
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