import 'package:dartnative/dartnative.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver, dnLog;

void registerResumeListener(void Function() callback) {
  WidgetsBinding.instance.addObserver(_LifecycleObserver(callback));
}

// A host can recreate its activity while keeping Dart alive. Rebind from the
// living isolate on resume; native code must never revive a pointer by itself.
final class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver(this.callback);
  final void Function() callback;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    try {
      callback();
    } catch (error) {
      dnLog('biometric_storage_kit: callback refresh failed: $error');
    }
  }

  @override
  void didChangeMetrics() {}
  @override
  void didChangePlatformBrightness() {}
  @override
  void didHaveMemoryPressure() {}
}
