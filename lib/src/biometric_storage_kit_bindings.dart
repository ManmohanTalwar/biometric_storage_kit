import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'platform.dart';
import 'lifecycle_stub.dart'
    if (dart.library.ui) 'lifecycle_native.dart'
    as lifecycle;

typedef _Dispatch = Void Function(Int64, Int32, Pointer<Utf8>);
typedef _Init = Int32 Function(Int64, Int32);
typedef _Request = Int32 Function(Int64, Pointer<Utf8>);
typedef _Cancel = Void Function(Int64);
final _dispatcher = Pointer.fromFunction<_Dispatch>(_dispatch);
void _dispatch(int id, int kind, Pointer<Utf8> payload) {
  try {
    BiometricStorageKitBindings.instance.deliver(id, payload.toDartString());
  } catch (_) {
    BiometricStorageKitBindings.instance.fail(
      id,
      const BiometricStorageException(
        'invalid_response',
        'Invalid native response.',
      ),
    );
  }
}

final class BiometricStorageKitBindings implements BiometricStoragePlatform {
  BiometricStorageKitBindings._();
  static final instance = BiometricStorageKitBindings._();
  static void loadSymbols() => instance._load();
  bool _loaded = false;
  late int Function(int, int) _initialize;
  late int Function(int, Pointer<Utf8>) _request;
  late void Function(int) _cancel;
  final _pending = <int, Completer<Object?>>{};
  void _load() {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    if (_loaded) {
      _checkStatus(_initialize(_dispatcher.address, 0));
      return;
    }
    final lib = Platform.isIOS
        ? DynamicLibrary.process()
        : DynamicLibrary.open('libbiometric_storage_kit.so');
    final init = lib.lookupFunction<_Init, int Function(int, int)>(
      'DNBiometricStorageKitInitialize',
    );
    final request = lib
        .lookupFunction<_Request, int Function(int, Pointer<Utf8>)>(
          'DNBiometricStorageKitRequest',
        );
    final cancel = lib.lookupFunction<_Cancel, void Function(int)>(
      'DNBiometricStorageKitCancel',
    );
    _checkStatus(init(_dispatcher.address, 1));
    _initialize = init;
    _request = request;
    _cancel = cancel;
    _loaded = true;
    lifecycle.registerResumeListener(_load);
  }

  void _checkStatus(int status) {
    if (status == 4) {
      for (final id in _pending.keys.toList()) {
        fail(
          id,
          const BiometricStorageException(
            'native_reset',
            'Native host was recreated; the previous outcome may be uncertain.',
          ),
        );
      }
    } else if (status != 0) {
      throw const BiometricStorageException(
        'unsupported_runtime',
        'Required callback-safety APIs are unavailable.',
      );
    }
  }

  @override
  Future<Object?> invoke(
    int id,
    String operation,
    Map<String, Object?> payload,
  ) async {
    _load();
    if (!_loaded) {
      throw UnsupportedError(
        'biometric_storage_kit supports iOS and Android only.',
      );
    }
    final completion = Completer<Object?>();
    _pending[id] = completion;
    final text = jsonEncode({
      'operation': operation,
      ...payload,
    }).toNativeUtf8();
    try {
      if (_request(id, text) != 0) {
        _pending.remove(id);
        throw const BiometricStorageException(
          'native_unavailable',
          'Native request could not be queued.',
        );
      }
    } finally {
      calloc.free(text);
    }
    return completion.future;
  }

  @override
  void cancel(int id) {
    if (_loaded && _pending.containsKey(id)) {
      _cancel(id);
      // A detached host may no longer be able to acknowledge cancellation.
      fail(
        id,
        const BiometricStorageException(
          'cancelled',
          'Operation cancelled; a mutation may already have committed.',
        ),
      );
    }
  }

  void fail(int id, Object error) {
    final completion = _pending.remove(id);
    if (completion != null && !completion.isCompleted) {
      completion.completeError(error);
    }
  }

  void deliver(int id, String payload) {
    final completion = _pending.remove(id);
    if (completion == null) return;
    try {
      final result = jsonDecode(payload) as Map<String, dynamic>;
      if (result['error'] case final Map<String, dynamic> error) {
        completion.completeError(
          BiometricStorageException(
            error['code'] as String,
            error['message'] as String,
            nativeCode: error['nativeCode'] as int?,
          ),
        );
      } else {
        completion.complete(result['value']);
      }
    } catch (error, stack) {
      completion.completeError(error, stack);
    }
  }
}
