import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../features/profile/profile_screen.dart';
import '../services/my_profile_service.dart';
import 'player_avatar_widget.dart';

/// The player's avatar and equipped frame, sized for an app bar.
///
/// Meant to go in every screen's `AppBar.actions` so the player's identity
/// is always on screen. Reads from [MyProfileService]'s shared stream, so
/// mounting it on more screens costs no extra Firestore reads.
class ProfileAvatarButton extends StatefulWidget {
  /// Whether tapping opens the profile. Off on the profile screen itself,
  /// where it would just stack a second copy on top.
  final bool openProfileOnTap;

  final double radius;

  /// Trailing gap. Defaults to the inset an `AppBar.actions` entry needs so
  /// it doesn't sit flush against the screen edge; the navigation shell
  /// passes 0 because its own overlay already positions the row.
  final double rightPadding;

  const ProfileAvatarButton({
    super.key,
    this.openProfileOnTap = true,
    this.radius = 16,
    this.rightPadding = 8,
  });

  @override
  State<ProfileAvatarButton> createState() => _ProfileAvatarButtonState();
}

class _ProfileAvatarButtonState extends State<ProfileAvatarButton> {
  // Held rather than built in `build()`: an app-bar widget rebuilds
  // constantly, and a stream created there would resubscribe every time.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _me =
      MyProfileService.instance.watchMe();

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2;

    return Padding(
      padding: EdgeInsets.only(right: widget.rightPadding),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _me,
        builder: (context, snapshot) {
          final data = snapshot.data?.data();

          // Reserves its slot while the first snapshot is in flight, so the
          // rest of the app bar doesn't shift once the avatar arrives.
          final avatar = data == null
              ? SizedBox(width: diameter, height: diameter)
              : PlayerAvatarWidget.fromPlayer(
                  data,
                  radius: widget.radius,
                  showGlow: false,
                );

          if (!widget.openProfileOnTap) {
            return Center(child: avatar);
          }

          return Center(
            child: InkWell(
              onTap: data == null ? null : _openProfile,
              customBorder: const CircleBorder(),
              child: avatar,
            ),
          );
        },
      ),
    );
  }
}
