import 'package:flutter/widgets.dart';

import 'app.dart';
import 'src/services/local_storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize local storage with Hive (with error handling)
  try {
    await LocalStorageService.init();
    print('✅ LocalStorageService inicializado correctamente');
  } catch (e) {
    print('❌ Error inicializando LocalStorageService: $e');
  }
  
  runApp(const SpendAntApp());
}
