import 'package:flutter/material.dart';

import '../services/avatar_service.dart';
import '../services/frame_service.dart';

class PlayerAvatarWidget extends StatelessWidget {
  final String? avatarId;
  final String? frameId;
  final String? bestLeagueId;
  final double radius;
  final bool showGlow;
  final bool showFrameEmoji;

  const PlayerAvatarWidget({
    super.key,
    required this.avatarId,
    this.frameId,
    this.bestLeagueId,
    this.radius = 24,
    this.showGlow = true,
    this.showFrameEmoji = false,
  });

  factory PlayerAvatarWidget.fromPlayer(
    Map<String, dynamic>? player, {
    Key? key,
    double radius = 24,
    bool showGlow = true,
    bool showFrameEmoji = false,
  }) {
    final data = player ?? {};

    return PlayerAvatarWidget(
      key: key,
      avatarId: data['avatarId']?.toString(),
      frameId: data['equippedFrame']?.toString(),
      bestLeagueId: data['bestLeagueId']?.toString(),
      radius: radius,
      showGlow: showGlow,
      showFrameEmoji: showFrameEmoji,
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeBestLeagueId =
        bestLeagueId == null || bestLeagueId!.trim().isEmpty
            ? 'bronze'
            : bestLeagueId!;

    final safeFrameId = FrameService.instance.safestEquippedFrame(
      equippedFrame: frameId,
      bestLeagueId: safeBestLeagueId,
    );

    final frame = FrameService.instance.frameById(safeFrameId);
    final avatar = AvatarService.instance.avatarById(avatarId ?? 'avatar_1');

    final frameColor = Color(frame.colorValue);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: EdgeInsets.all(radius * 0.08),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: frameColor,
              width: radius * 0.08,
            ),
            boxShadow: showGlow
                ? [
                    BoxShadow(
                      color: frameColor.withOpacity(0.28),
                      blurRadius: radius * 0.28,
                    ),
                  ]
                : null,
          ),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: Colors.white.withOpacity(0.85),
            child: Text(
              avatar.emoji,
              style: TextStyle(
                fontSize: radius * 0.92,
              ),
            ),
          ),
        ),
        if (showFrameEmoji)
          Positioned(
            right: -radius * 0.10,
            top: -radius * 0.10,
            child: Container(
              padding: EdgeInsets.all(radius * 0.08),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                shape: BoxShape.circle,
                border: Border.all(
                  color: frameColor.withOpacity(0.55),
                ),
              ),
              child: Text(
                frame.emoji,
                style: TextStyle(
                  fontSize: radius * 0.42,
                ),
              ),
            ),
          ),
      ],
    );
  }
}