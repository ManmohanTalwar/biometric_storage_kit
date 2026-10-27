import 'dart:convert';
import 'dart:io';
import 'package:dartnative/dartnative.dart';
import 'package:biometric_storage_kit/biometric_storage_kit.dart';
import 'dartnative_plugin_registrant.dart';
void main() {
  DartNativePluginRegistrant.registerAll();
  runApp(const RegistryCheck());
}
class RegistryCheck extends StatefulWidget {
  const RegistryCheck({super.key});
  @override
  State<RegistryCheck> createState() => RegistryState();
}
class RegistryState extends State<RegistryCheck> {
  final storage = BiometricStorage(namespace: 'registry-validation');
  String status = 'Preparing synthetic registry checks';
  void require(bool value) { if (!value) throw StateError('Verification mismatch'); }
  Future<bool> check(String name, Future<void> Function() action) async {
    String? error;
    try { await action(); } catch (e) { error = e is BiometricStorageException ? e.code : e.runtimeType.toString(); }
    final row = jsonEncode({'case':name, 'passed':error == null, 'error':error,'utc':DateTime.now().toUtc().toIso8601String()});
    print('BIOREG $row');
    await File('${Directory.systemTemp.path}/bioreg-results.jsonl').writeAsString('$row\n', mode:FileMode.append, flush:true);
    setState(() => status = '${error == null ? 'PASS' : 'FAIL'}: $name');
    return error == null;
  }
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds:1), () async {
      if (!await check('availability', () async { await storage.checkAvailability(); })) return;
      if (!await check('initial-absence', () async { require(await storage.read('synthetic') == null); })) return;
      if (Platform.isAndroid) {
        if (!await check('write', () => storage.write('synthetic', 'Registry • नमस्ते • 🔐'))) return;
        if (!await check('read', () async { require(await storage.read('synthetic') == 'Registry • नमस्ते • 🔐'); })) return;
      }
      await check('delete-and-absence', () async { await storage.delete('synthetic'); require(await storage.read('synthetic') == null); });
    });
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar:AppBar(title:const Text('Registry storage check')),body:Center(child:Text(status)));
  @override
  void dispose() { storage.dispose(); super.dispose(); }
}
