import 'dart:async';
import 'package:biometric_storage_kit/biometric_storage_kit.dart';
import 'package:biometric_storage_kit/src/platform.dart';
import 'package:test/test.dart';

class Transport implements BiometricStoragePlatform {
  final calls = <(int, String, Map<String, Object?>)>[];
  final cancelled = <int>[];
  Future<Object?> Function(String, Map<String, Object?>)? handler;
  @override
  Future<Object?> invoke(int id, String op, Map<String, Object?> data) {
    calls.add((id, op, data));
    return handler?.call(op, data) ?? Future.value();
  }

  @override
  void cancel(int id) {
    cancelled.add(id);
  }
}

void main() {
  late Transport native;
  late BiometricStorage storage;
  setUp(() {
    native = Transport();
    storage = BiometricStorage(namespace: 'tests', platform: native);
  });
  test('Unicode and empty strings are values; absence is distinct', () async {
    for (final value in ['नया 📝', '', null]) {
      native.handler = (_, _) async => value;
      expect(await storage.read('key'), value);
    }
  });
  test(
    'malformed Unicode never aliases another name or changes a secret',
    () async {
      for (final malformed in ['\uD800', '\uDC00', 'x\uD800y']) {
        expect(
          () => BiometricStorage(namespace: malformed, platform: native),
          throwsArgumentError,
        );
        await expectLater(storage.read(malformed), throwsArgumentError);
        await expectLater(storage.write('key', malformed), throwsArgumentError);
        await expectLater(
          storage.read(
            'key',
            prompt: BiometricPromptOptions(reason: malformed),
          ),
          throwsArgumentError,
        );
      }
      expect(native.calls, isEmpty);
      await storage.write('📝', '🙂');
      expect(native.calls.single.$3['value'], '🙂');
    },
  );
  test('invalid identifiers and oversized secret never reach native', () async {
    expect(
      () => BiometricStorage(namespace: '', platform: native),
      throwsArgumentError,
    );
    await expectLater(storage.read(''), throwsArgumentError);
    await expectLater(storage.write('a', '🙂' * 20000), throwsArgumentError);
    expect(native.calls, isEmpty);
  });
  test(
    'legacy traversal rejected; legacy reads use original name only',
    () async {
      await expectLater(
        storage.readLegacyFlutter('../other'),
        throwsArgumentError,
      );
      await expectLater(storage.readLegacyFlutter('a/b'), throwsArgumentError);
      await storage.readLegacyFlutter('encoded.name==');
      expect(native.calls.single.$2, 'readLegacy');
      expect(native.calls.single.$3['name'], 'encoded.name==');
    },
  );
  test('error does not become missing or trigger a second operation', () async {
    native.handler = (_, _) async => throw const BiometricStorageException(
      'key_invalidated',
      'Key unavailable.',
    );
    await expectLater(
      storage.read('key'),
      throwsA(
        isA<BiometricStorageException>().having(
          (e) => e.code,
          'code',
          'key_invalidated',
        ),
      ),
    );
    expect(native.calls.map((c) => c.$2), ['read']);
  });
  test('overlapping operations fail without queuing secret writes', () async {
    final pending = Completer<Object?>();
    native.handler = (_, _) => pending.future;
    final read = storage.read('key');
    await expectLater(
      storage.write('key', 'secret'),
      throwsA(
        isA<BiometricStorageException>().having((e) => e.code, 'code', 'busy'),
      ),
    );
    expect(native.calls.length, 1);
    pending.complete('value');
    expect(await read, 'value');
  });
  test('cancel and dispose target only this instance active request', () async {
    final pending = Completer<Object?>();
    native.handler = (_, _) => pending.future;
    final read = storage.read('key');
    storage.dispose();
    expect(native.cancelled, [native.calls.single.$1]);
    pending.completeError(
      const BiometricStorageException('cancelled', 'Cancelled.'),
    );
    await expectLater(read, throwsA(isA<BiometricStorageException>()));
    await expectLater(storage.read('key'), throwsStateError);
  });
  test('prompt reuse is bounded and forwarded only as iOS duration', () async {
    await expectLater(
      storage.read(
        'key',
        prompt: const BiometricPromptOptions(
          iosReuseDuration: Duration(minutes: 6),
        ),
      ),
      throwsArgumentError,
    );
    await storage.write(
      'key',
      '',
      prompt: const BiometricPromptOptions(
        iosReuseDuration: Duration(seconds: 60),
      ),
    );
    expect(native.calls.single.$3['reuseSeconds'], 60);
    expect(native.calls.single.$3['value'], '');
  });
  test('availability unknown is not silently available', () async {
    native.handler = (_, _) async => 'future_status';
    expect(await storage.checkAvailability(), BiometricAvailability.unknown);
  });
  test('delete names exactly one current record', () async {
    await storage.delete('one');
    expect(native.calls.single.$2, 'delete');
    expect(native.calls.single.$3['namespace'], 'tests');
    expect(native.calls.single.$3['name'], 'one');
  });
  test('invalid native value is a failure, not absence', () async {
    native.handler = (_, _) async => false;
    await expectLater(
      storage.read('key'),
      throwsA(isA<BiometricStorageException>()),
    );
  });
}
