import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app.dart';
import 'src/services/app_notification_service.dart';
import 'firebase_options.dart';
import 'src/services/cloud_sync_service.dart';
import 'src/services/local_notification_service.dart';
import 'src/services/local_storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local storage with Hive (with error handling)
  try {
    await LocalStorageService.init();
    debugPrint('LocalStorageService inicializado correctamente');
  } catch (e) {
    debugPrint('Error inicializando LocalStorageService: $e');
  }

  try {
    await LocalNotificationService.initialize();
    await AppNotificationService.initialize();
    debugPrint('Servicios de notificaciones inicializados correctamente');
  } catch (e) {
    debugPrint('Error inicializando notificaciones: $e');
  }

  if (CloudSyncService.isSupportedPlatform) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('Firebase inicializado correctamente');
    } catch (e) {
      debugPrint('Error inicializando Firebase: $e');
    }
  } else {
    debugPrint('Firebase no esta disponible en esta plataforma');
  }

  runApp(const SpendAntApp());
}
