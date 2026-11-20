import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the phone has no network at all: no wifi, no mobile data,
/// nothing. A network that is up but reaches nowhere is not offline by
/// this measure; the calls that fail on it say so themselves.
bool isOffline(List<ConnectivityResult> networks) =>
    networks.every((network) => network == ConnectivityResult.none);

/// Tells the app when the phone loses its connection and when it has one
/// again.
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  /// How long the phone must stay without a network before the app says
  /// so. Passing from wifi to mobile data reports none for a moment.
  static const Duration offlineAfter = Duration(seconds: 2);

  /// True while the phone has no network.
  final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  StreamSubscription<List<ConnectivityResult>>? _changes;
  Timer? _pending;

  /// Starts watching. Safe to call more than once.
  Future<void> start() async {
    if (_changes != null) return;
    try {
      final connectivity = Connectivity();
      _changes = connectivity.onConnectivityChanged.listen(_onChange);
      _onChange(await connectivity.checkConnectivity());
    } catch (_) {
      // A platform with no way to tell is treated as online.
    }
  }

  void _onChange(List<ConnectivityResult> networks) {
    _pending?.cancel();
    if (!isOffline(networks)) {
      offline.value = false;
      return;
    }
    _pending = Timer(offlineAfter, () => offline.value = true);
  }
}
