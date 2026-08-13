import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../features/profile/profile_screen.dart';
import '../services/my_profile_service.dart';
import '../theme/app_theme.dart';
import 'player_avatar_widget.dart';

/// The player's name and avatar, sized for an app bar.
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

  /// Whether the player's name shows beside the avatar. The name is the
  /// player's own, so it says more than a static "Profile" label would —
  /// but it costs horizontal room, and screens whose app bar is already
  /// crowded can drop it and keep just the avatar.
  final bool showName;

  const ProfileAvatarButton({
    super.key,
    this.openProfileOnTap = true,
    this.radius = 16,
    this.rightPadding = 8,
    this.showName = true,
  });

  @override
  State<ProfileAvatarButton> createState() => _ProfileAvatarButtonState();
}

class _ProfileAvatarButtonState extends State<ProfileAvatarButton> {
  /// Long names are cut with an ellipsis rather than allowed to push the
  /// rest of the bar around — a name may be up to 20 characters.
  static const double _maxNameWidth = 74;

  // Held rather than built in `build()`: an app-bar widget rebuilds
  // constantly, and a stream created there would resubscribe every time.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _me =
      MyProfileService.instance.watchMe();

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  String _nameFrom(Map<String, dynamic> data) {
    final username = (data['username'] ?? '').toString().trim();
    if (username.isNotEmpty) return username;
    return (data['displayName'] ?? '').toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(right: widget.rightPadding),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _me,
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          final name = data == null ? '' : _nameFrom(data);

          // Reserves its slot while the first snapshot is in flight, so the
          // rest of the app bar doesn't shift once the avatar arrives.
          final avatar = data == null
              ? SizedBox(width: diameter, height: diameter)
              : PlayerAvatarWidget.fromPlayer(
                  data,
                  radius: widget.radius,
                  showGlow: false,
                );

          // Sin nombre todavia (o desactivado) no hay pildora que montar:
          // el avatar va solo, como cualquier otra accion de la barra.
          if (!widget.showName || name.isEmpty) {
            return Center(
              child: widget.openProfileOnTap
                  ? InkWell(
                      onTap: data == null ? null : _openProfile,
                      customBorder: const CircleBorder(),
                      child: avatar,
                    )
                  : avatar,
            );
          }

          // El avatar se monta sobre el borde derecho de la pildora en vez
          // de ir dentro: sobresale, manda en la jerarquia, y el marco
          // equipado se ve entero sin que el fondo lo recorte.
          //
          // Cuanto asoma el avatar por fuera de la pildora. El hueco va como
          // margen del contenedor y no como alineacion del Stack: alineando
          // al borde derecho, el avatar queda *dentro* de la pildora y el
          // nombre acaba por debajo.
          final protrusion = diameter * 0.32;

          // El texto tiene que parar antes de donde empieza el avatar: lo
          // que este cubre por dentro, mas un respiro.
          final textGutter = diameter - protrusion + 8;

          final content = Stack(
            alignment: Alignment.centerRight,
            clipBehavior: Clip.none,
            children: [
              Container(
                margin: EdgeInsets.only(right: protrusion),
                padding: EdgeInsets.only(
                  left: 12,
                  right: textGutter,
                  top: 5,
                  bottom: 5,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(context.radii.pill),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxNameWidth),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
              avatar,
            ],
          );

          if (!widget.openProfileOnTap) {
            return Center(child: content);
          }

          return Center(
            child: InkWell(
              onTap: data == null ? null : _openProfile,
              borderRadius: BorderRadius.circular(context.radii.pill),
              child: content,
            ),
          );
        },
      ),
    );
  }
}
