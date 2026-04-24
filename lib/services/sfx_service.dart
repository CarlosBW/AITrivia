import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class SfxService {
  SfxService._();
  static final SfxService instance = SfxService._();

  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;

  /// Llama una vez al inicio (main o primera pantalla).
  Future<void> init() async {
    if (_ready) return;
    _ready = true;

    try {
      // Para SFX cortos: baja latencia
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setPlayerMode(PlayerMode.lowLatency);

      // Precarga (opcional pero recomendado)
      await _player.audioCache.loadAll([
        'sfx/correct.mp3',
        'sfx/wrong.mp3',
        'sfx/timeout.mp3',
      ]);
    } catch (e) {
      debugPrint('SfxService init error: $e');
    }
  }

  Future<void> playCorrect() => _play('sfx/correct.mp3');
  Future<void> playWrong() => _play('sfx/wrong.mp3');
  Future<void> playTimeout() => _play('sfx/timeout.mp3');

  Future<void> _play(String assetPath) async {
    try {
      // Si aún no se llamó init por algún motivo, intenta inicializar aquí.
      if (!_ready) {
        await init();
      }

      // corta cualquier sonido previo y reproduce el nuevo
      await _player.stop();
      await _player.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint('SfxService play error ($assetPath): $e');
    }
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
