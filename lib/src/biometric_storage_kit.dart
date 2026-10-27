import 'dart:async';
import 'dart:convert';
import 'biometric_storage_kit_bindings.dart';
import 'platform.dart';

bool _validUnicode(String value) => utf8.decode(utf8.encode(value)) == value;

final class BiometricPromptOptions {
  const BiometricPromptOptions({
    this.reason = 'Authenticate to access protected storage',
    this.title = 'Protected storage',
    this.cancelLabel = 'Cancel',
    this.iosReuseDuration = Duration.zero,
  });
  final String reason;
  final String title;
  final String cancelLabel;

  /// iOS may reuse a recent device-unlock biometric match, not arbitrary in-app
  /// authentication. Android always authenticates each cryptographic operation.
  final Duration iosReuseDuration;
  Map<String, Object?> toJson() {
    for (final value in [reason, title, cancelLabel]) {
      if (!_validUnicode(value) ||
          value.trim().isEmpty ||
          utf8.encode(value).length > 1024 ||
          value.contains('\u0000')) {
        throw ArgumentError(
          'Prompt text must be nonempty, valid Unicode, NUL-free and at most 1024 UTF-8 bytes.',
        );
      }
    }
    if (iosReuseDuration < Duration.zero ||
        iosReuseDuration > const Duration(minutes: 5)) {
      throw ArgumentError(
        'iOS reuse duration must be between zero and five minutes.',
      );
    }
    return {
      'reason': reason,
      'title': title,
      'cancelLabel': cancelLabel,
      'reuseSeconds': iosReuseDuration.inMilliseconds / 1000,
    };
  }
}

/// Biometric-protected UTF-8 strings, with no automatic recovery or key rotation.
/// Native operations are serialized across all instances; overlap fails `busy`.
final class BiometricStorage {
  BiometricStorage({
    this.namespace = 'default',
    BiometricStoragePlatform? platform,
  }) : _platform = platform ?? BiometricStorageKitBindings.instance {
    _validateName(namespace, 'namespace', 128);
  }
  final String namespace;
  final BiometricStoragePlatform _platform;
  static int _sequence = DateTime.now().microsecondsSinceEpoch;
  int? _active;
  bool _disposed = false;
  static void _validateName(String value, String field, int maxBytes) {
    if (!_validUnicode(value) ||
        value.isEmpty ||
        value.contains('\u0000') ||
        utf8.encode(value).length > maxBytes) {
      throw ArgumentError(
        '$field must be nonempty, valid Unicode, NUL-free and at most $maxBytes UTF-8 bytes.',
      );
    }
  }

  Map<String, Object?> _payload(String name, BiometricPromptOptions prompt) {
    _validateName(name, 'name', 512);
    return {'namespace': namespace, 'name': name, ...prompt.toJson()};
  }

  Future<Object?> _perform(
    String operation,
    Map<String, Object?> payload,
  ) async {
    if (_disposed) throw StateError('BiometricStorage is disposed.');
    if (_active != null) {
      throw const BiometricStorageException(
        'busy',
        'Another storage operation is active.',
      );
    }
    final id = ++_sequence;
    _active = id;
    try {
      return await _platform
          .invoke(id, operation, payload)
          .timeout(
            const Duration(minutes: 3),
            onTimeout: () {
              _platform.cancel(id);
              throw const BiometricStorageException(
                'timeout',
                'Operation timed out; a mutation may already have committed.',
              );
            },
          );
    } finally {
      if (_active == id) _active = null;
    }
  }

  Future<BiometricAvailability> checkAvailability() async {
    final value = await _perform('availability', {});
    return BiometricAvailability.values.firstWhere(
      (e) => e.name == value,
      orElse: () => BiometricAvailability.unknown,
    );
  }

  Future<String?> read(
    String name, {
    BiometricPromptOptions prompt = const BiometricPromptOptions(),
  }) async {
    final value = await _perform('read', _payload(name, prompt));
    if (value != null && value is! String) {
      throw const BiometricStorageException(
        'invalid_response',
        'Invalid native response.',
      );
    }
    return value as String?;
  }

  Future<void> write(
    String name,
    String value, {
    BiometricPromptOptions prompt = const BiometricPromptOptions(),
  }) async {
    final payload = _payload(name, prompt);
    if (!_validUnicode(value) || utf8.encode(value).length > 65536) {
      throw ArgumentError(
        'Secret must be valid Unicode and at most 65536 UTF-8 bytes.',
      );
    }
    await _perform('write', {...payload, 'value': value});
  }

  /// Explicit deletion is not an authentication gate. It can remove inaccessible
  /// current-format records. Never used automatically after a read/auth error.
  Future<void> delete(String name) async {
    await _perform('delete', _payload(name, const BiometricPromptOptions()));
  }

  /// Read-only import source for biometric_storage 5.0.1, under the SAME signed app
  /// identity and original name. Existing OS protection is preserved. Never
  /// deletes or rewrites the legacy record. Does not certify upgrade continuity.
  Future<String?> readLegacyFlutter(
    String name, {
    BiometricPromptOptions prompt = const BiometricPromptOptions(),
  }) async {
    if (name.contains('/') ||
        name.contains('\\') ||
        name == '.' ||
        name == '..') {
      throw ArgumentError('Legacy name must be one safe filename component.');
    }
    final value = await _perform('readLegacy', _payload(name, prompt));
    if (value != null && value is! String) {
      throw const BiometricStorageException(
        'invalid_response',
        'Invalid native response.',
      );
    }
    return value as String?;
  }

  /// Best effort. Cancellation cannot undo an already committed write/delete.
  void cancelPending() {
    final id = _active;
    if (id != null) _platform.cancel(id);
  }

  void dispose() {
    if (!_disposed) {
      _disposed = true;
      cancelPending();
    }
  }
}
