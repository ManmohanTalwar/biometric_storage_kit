enum BiometricAvailability {
  available,
  notEnrolled,
  unavailable,
  lockedOut,
  passcodeNotSet,
  unknown,
}

final class BiometricStorageException implements Exception {
  const BiometricStorageException(this.code, this.message, {this.nativeCode});
  final String code;
  final String message;
  final int? nativeCode;
  @override
  String toString() => 'BiometricStorageException($code, $message)';
}

/// Transport seam. Payloads contain secrets: implementations must never log them.
abstract interface class BiometricStoragePlatform {
  Future<Object?> invoke(
    int id,
    String operation,
    Map<String, Object?> payload,
  );
  void cancel(int id);
}
