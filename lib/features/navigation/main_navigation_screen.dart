import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../home/home_screen.dart';
import '../shop/coin_shop_screen.dart';
import '../social/friends_screen.dart';
import '../versus/pvp_screen.dart';
import '../versus/match_lobby_screen.dart';
import '../solo/solo_screen.dart';
import '../notifications/notifications_screen.dart';
import '../../services/notification_service.dart';
import '../../services/analytics_service.dart';
import '../../widgets/notification_bell_button.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/language_switch.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _index = 0;
  bool _isOpeningNotifications = false;

  int _lastUnreadCount = 0;
  bool _hasInitializedUnread = false;
  bool _showNotificationOverlay = false;
  Timer? _overlayTimer;

  String? _lastNotificationId;
  bool _showingChallengeAcceptedDialog = false;
  bool _navigatingToAcceptedChallenge = false;

  final Set<int> _visitedTabs = {0};

  // Held rather than built in `build()`: this is the navigation shell, so it
  // rebuilds on every tab switch and twice more per notification overlay,
  // and each rebuild used to re-subscribe this query from scratch.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _unreadNotifications =
      NotificationService.instance.watchMyUnreadNotifications(limit: 99);

  static const _tabNames = ['home', 'solo', 'pvp', 'friends', 'store'];

  void _selectTab(int index) {
    if (_index == index) return;

    setState(() {
      _index = index;
      _visitedTabs.add(index);
    });

    final tabName = index >= 0 && index < _tabNames.length
        ? _tabNames[index]
        : 'unknown';

    AnalyticsService.instance
        .logNavTabSelected(tab: tabName)
        .catchError((_) {});
  }

  Widget _lazyTab({
    required int tabIndex,
    required Widget child,
  }) {
    if (!_visitedTabs.contains(tabIndex)) {
      return const SizedBox.shrink();
    }

    return child;
  }

  Future<void> _checkSpecialNotifications(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_showingChallengeAcceptedDialog) return;
    if (_navigatingToAcceptedChallenge) return;
    if (_isOpeningNotifications) return;
    if (snap.docs.isEmpty) return;

    final doc = snap.docs.first;

    if (_lastNotificationId == doc.id) return;
    _lastNotificationId = doc.id;

    final notification = doc.data();
    final type = (notification['type'] ?? '').toString();

    if (type != 'realtime_invite_accepted') return;

    final payload = Map<String, dynamic>.from(notification['data'] ?? {});
    final matchId = (payload['matchId'] ?? '').toString();

    if (matchId.isEmpty || !mounted) return;

    _showingChallengeAcceptedDialog = true;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        final body = (notification['body'] ?? '').toString();

        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.sports_esports,
                color: Theme.of(dialogContext).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.navChallengeAcceptedTitle),
              ),
            ],
          ),
          content: Text(
            body.isEmpty ? l10n.navChallengeAcceptedBodyFallback : body,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: Text(l10n.navLater),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);

                if (!mounted) return;

                setState(() {
                  _navigatingToAcceptedChallenge = true;
                  _showNotificationOverlay = false;
                });

                try {
                  await NotificationService.instance.markAsRead(
                    notificationId: doc.id,
                  );
                } catch (_) {}

                if (!mounted) return;

                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MatchLobbyScreen(
                      matchId: matchId,
                    ),
                  ),
                );

                if (!mounted) return;

                setState(() {
                  _navigatingToAcceptedChallenge = false;
                });
              },
              child: Text(l10n.navPlayNow),
            ),
          ],
        );
      },
    );

    _showingChallengeAcceptedDialog = false;
  }

  Future<void> _openNotifications() async {
    if (_isOpeningNotifications) return;

    setState(() {
      _isOpeningNotifications = true;
      _showNotificationOverlay = false;
    });

    _overlayTimer?.cancel();

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const NotificationsScreen(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isOpeningNotifications = false);
      }
    }
  }

  void _handleUnreadCountChanged(int unreadCount) {
    if (!_hasInitializedUnread) {
      _hasInitializedUnread = true;
      _lastUnreadCount = unreadCount;
      return;
    }

    if (unreadCount > _lastUnreadCount && !_isOpeningNotifications) {
      _showBigNotificationOverlay();
    }

    _lastUnreadCount = unreadCount;
  }

  void _showBigNotificationOverlay() {
    _overlayTimer?.cancel();

    if (!mounted) return;

    setState(() => _showNotificationOverlay = true);

    _overlayTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      setState(() => _showNotificationOverlay = false);
    });
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _unreadNotifications,
        builder: (context, snap) {
          final unreadSnapshot = snap.data;
          final unreadCount = unreadSnapshot?.docs.length ?? 0;

          if (unreadSnapshot != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _checkSpecialNotifications(unreadSnapshot);
            });
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleUnreadCountChanged(unreadCount);
          });

          return Stack(
            children: [
              IndexedStack(
                index: _index,
                children: [
                  _lazyTab(
                    tabIndex: 0,
                    child: const HomeScreen(),
                  ),
                  _lazyTab(
                    tabIndex: 1,
                    child: const SoloScreen(),
                  ),
                  _lazyTab(
                    tabIndex: 2,
                    child: const PvPScreen(),
                  ),
                  _lazyTab(
                    tabIndex: 3,
                    child: const FriendsScreen(),
                  ),
                  // El perfil salio de la barra: se abre desde el avatar
                  // que ahora esta en la cabecera de todas las pantallas,
                  // y este hueco pasa a la tienda.
                  _lazyTab(
                    tabIndex: 4,
                    child: const CoinShopScreen(embeddedInShell: true),
                  ),
                ],
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 6,
                right: 10,
                child: Material(
                  color: Colors.transparent,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const LanguageSwitch(),
                      const SizedBox(width: 8),
                      NotificationBellButton(
                        unreadCount: unreadCount,
                        onPressed: _isOpeningNotifications
                            ? () {}
                            : _openNotifications,
                      ),
                      const SizedBox(width: 8),
                      // Aquí y no en el AppBar de cada tab: esta fila se
                      // dibuja por encima del contenido, así que un avatar
                      // en el AppBar quedaba tapado por la campana.
                      const ProfileAvatarButton(rightPadding: 0),
                    ],
                  ),
                ),
              ),
              if (_showNotificationOverlay) const _NewNotificationOverlay(),
            ],
          );
        },
      ),
      bottomNavigationBar: _BottomNavBar(
        selectedIndex: _index,
        onSelect: _selectTab,
      ),
    );
  }
}

class _NavGlyph extends StatelessWidget {
  final Color color;
  final CustomPainter Function(Color color) painter;

  const _NavGlyph({required this.color, required this.painter});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(painter: painter(color)),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _BottomNavBar({
    required this.selectedIndex,
    required this.onSelect,
  });

  static const _soloIndex = 1;

  Widget _buildItem(
    BuildContext context,
    int logicalIndex,
    CustomPainter Function(Color color) painter,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = logicalIndex == selectedIndex;
    final color =
        selected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return Expanded(
      child: InkWell(
        onTap: () => onSelect(logicalIndex),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NavGlyph(color: color, painter: painter),
            const SizedBox(height: 4),
            AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.surfaceContainerHighest),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  _buildItem(context, 0, (c) => _HomeIconPainter(c)),
                  _buildItem(context, 2, (c) => _SwordsPainter(c)),
                  const Expanded(child: SizedBox()),
                  _buildItem(context, 3, (c) => _UsersIconPainter(c)),
                  _buildItem(context, 4, (c) => _StoreIconPainter(c)),
                ],
              ),
            ),
            Positioned(
              top: -6,
              child: GestureDetector(
                onTap: () => onSelect(_soloIndex),
                child: _AppIconFab(selected: selectedIndex == _soloIndex),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppIconFab extends StatelessWidget {
  final bool selected;

  const _AppIconFab({required this.selected});

  @override
  Widget build(BuildContext context) {
    const size = 62.0;

    return AnimatedScale(
      scale: selected ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6C4FF2), Color(0xFF8A6BFF)],
          ),
          border: Border.all(
            color: selected ? const Color(0xFFEF9F27) : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const CustomPaint(painter: _AppLogoPainter()),
      ),
    );
  }
}

// Mirrors the app-icon mark (assets/icon/icon.png): a "?" glyph with a
// small sparkle accent, scaled down for the nav bar.
class _AppLogoPainter extends CustomPainter {
  const _AppLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    const glyphColor = Color(0xFFF3EEFF);
    const sparkColor = Color(0xFFEF9F27);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          color: glyphColor,
          fontSize: s * 0.64,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        s * 0.42 - textPainter.width / 2,
        s * 0.50 - textPainter.height / 2,
      ),
    );

    final sparkCenter = Offset(s * 0.72, s * 0.32);
    final sparkR = s * 0.125;
    const points = [
      Offset(0.50, 0.00),
      Offset(0.61, 0.39),
      Offset(1.00, 0.50),
      Offset(0.61, 0.61),
      Offset(0.50, 1.00),
      Offset(0.39, 0.61),
      Offset(0.00, 0.50),
      Offset(0.39, 0.39),
    ];

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = sparkCenter +
          Offset(
            (points[i].dx - 0.5) * sparkR * 2,
            (points[i].dy - 0.5) * sparkR * 2,
          );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();

    canvas.drawPath(path, Paint()..color = sparkColor);
  }

  @override
  bool shouldRepaint(covariant _AppLogoPainter oldDelegate) => false;
}

class _HomeIconPainter extends CustomPainter {
  final Color color;

  _HomeIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()
      ..color = color
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(
      Path()
        ..moveTo(s * 0.10, s * 0.52)
        ..lineTo(s * 0.44, s * 0.16)
        ..quadraticBezierTo(s * 0.5, s * 0.10, s * 0.56, s * 0.16)
        ..lineTo(s * 0.90, s * 0.52),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(s * 0.20, s * 0.44)
        ..lineTo(s * 0.20, s * 0.80)
        ..quadraticBezierTo(s * 0.20, s * 0.88, s * 0.28, s * 0.88)
        ..lineTo(s * 0.72, s * 0.88)
        ..quadraticBezierTo(s * 0.80, s * 0.88, s * 0.80, s * 0.80)
        ..lineTo(s * 0.80, s * 0.44),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(s * 0.42, s * 0.88)
        ..lineTo(s * 0.42, s * 0.64)
        ..quadraticBezierTo(s * 0.42, s * 0.60, s * 0.46, s * 0.60)
        ..lineTo(s * 0.54, s * 0.60)
        ..quadraticBezierTo(s * 0.58, s * 0.60, s * 0.58, s * 0.64)
        ..lineTo(s * 0.58, s * 0.88),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

// Ported 1:1 from the Tabler "swords" outline icon (24x24 viewBox).
class _SwordsPainter extends CustomPainter {
  final Color color;

  _SwordsPainter(this.color);

  static const _path1 = [
    Offset(21, 3),
    Offset(21, 8),
    Offset(10, 17),
    Offset(6, 21),
    Offset(3, 18),
    Offset(7, 14),
    Offset(16, 3),
    Offset(21, 3),
  ];
  static const _path2 = [Offset(5, 13), Offset(11, 19)];
  static const _path3 = [
    Offset(14.32, 17.32),
    Offset(18, 21),
    Offset(21, 18),
    Offset(17.635, 14.635),
  ];
  static const _path4 = [
    Offset(10, 5.5),
    Offset(8, 3),
    Offset(3, 3),
    Offset(3, 8),
    Offset(6, 10.5),
  ];

  void _drawPolyline(
    Canvas canvas,
    Paint paint,
    List<Offset> points,
    double s,
  ) {
    final path = Path()
      ..moveTo(points.first.dx / 24 * s, points.first.dy / 24 * s);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx / 24 * s, p.dy / 24 * s);
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()
      ..color = color
      ..strokeWidth = s * (2 / 24)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    _drawPolyline(canvas, paint, _path1, s);
    _drawPolyline(canvas, paint, _path2, s);
    _drawPolyline(canvas, paint, _path3, s);
    _drawPolyline(canvas, paint, _path4, s);
  }

  @override
  bool shouldRepaint(covariant _SwordsPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _UsersIconPainter extends CustomPainter {
  final Color color;

  _UsersIconPainter(this.color);

  void _drawPerson(
    Canvas canvas,
    Paint paint,
    Offset headCenter,
    double headR,
    Offset shoulderCenter,
    double shoulderR,
  ) {
    canvas.drawCircle(headCenter, headR, paint);
    canvas.drawArc(
      Rect.fromCircle(center: shoulderCenter, radius: shoulderR),
      math.pi,
      math.pi,
      false,
      paint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()
      ..color = color
      ..strokeWidth = s * 0.08
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    _drawPerson(
      canvas,
      paint,
      Offset(s * 0.30, s * 0.30),
      s * 0.15,
      Offset(s * 0.30, s * 0.80),
      s * 0.22,
    );
    _drawPerson(
      canvas,
      paint,
      Offset(s * 0.72, s * 0.34),
      s * 0.12,
      Offset(s * 0.72, s * 0.80),
      s * 0.18,
    );
  }

  @override
  bool shouldRepaint(covariant _UsersIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Storefront with an awning, for the store tab. Replaced the person glyph
/// when the profile moved out of the bar and into the header avatar.
///
/// The awning's scalloped edge is drawn as three arcs rather than a plain
/// line: at this size it is the detail that makes the shape read as a shop
/// instead of a house.
class _StoreIconPainter extends CustomPainter {
  final Color color;

  _StoreIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()
      ..color = color
      ..strokeWidth = s * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Alto igualado al del resto de la barra: la casa ocupa de 0.10 a 0.88
    // y los amigos de 0.15 a 0.80. Este iba de 0.28 a 0.84 — mas corto y
    // con el centro 7 puntos mas abajo, que es por lo que se veia
    // descolgado respecto a sus vecinos.
    const awningTop = 0.14;
    const awningBottom = 0.38;
    const bodyTop = 0.44;
    const bodyBottom = 0.86;

    const awningLeft = 0.08;
    const awningRight = 0.92;

    // Toldo: se ensancha hacia abajo y sobresale del cuerpo. Sin trazar su
    // base, que la cierra el feston.
    final awning = Path()
      ..moveTo(s * awningLeft, s * awningBottom)
      ..lineTo(s * 0.18, s * awningTop)
      ..lineTo(s * 0.82, s * awningTop)
      ..lineTo(s * awningRight, s * awningBottom);
    canvas.drawPath(awning, paint);

    // Feston: cuatro ondas que hacen las veces de borde inferior del toldo.
    const scallops = 4;
    const scallopWidth = (awningRight - awningLeft) / scallops;
    for (var i = 0; i < scallops; i++) {
      final left = awningLeft + scallopWidth * i;
      canvas.drawArc(
        Rect.fromLTRB(
          s * left,
          s * (awningBottom - 0.06),
          s * (left + scallopWidth),
          s * (awningBottom + 0.06),
        ),
        0,
        math.pi,
        false,
        paint,
      );
    }

    // Cuerpo en forma de U: el feston ya cierra la parte de arriba, asi que
    // trazar tambien su techo duplicaria la linea.
    final body = Path()
      ..moveTo(s * 0.18, s * bodyTop)
      ..lineTo(s * 0.18, s * bodyBottom)
      ..lineTo(s * 0.82, s * bodyBottom)
      ..lineTo(s * 0.82, s * bodyTop);
    canvas.drawPath(body, paint);
  }

  @override
  bool shouldRepaint(covariant _StoreIconPainter oldDelegate) =>
      oldDelegate.color != color;
}


class _NewNotificationOverlay extends StatelessWidget {
  const _NewNotificationOverlay();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.75, end: 1.0),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: child,
            );
          },
          child: AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 250),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 22,
              ),
              decoration: BoxDecoration(
                color: context.appColors.reward,
                borderRadius: BorderRadius.circular(context.radii.lg),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.28),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.notifications_active,
                    color: Color(0xFF412402),
                    size: 58,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.navNewNotificationTitle,
                    style: context.heading(23, color: Color(0xFF412402)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.navNewNotificationSubtitle,
                    style: const TextStyle(
                      color: Color(0xFF412402),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}