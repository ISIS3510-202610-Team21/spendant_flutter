import 'package:flutter/widgets.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'src/services/app_notification_service.dart';
import 'src/services/cloud_sync_service.dart';
import 'src/services/google_pay_expense_import_service.dart';
import 'src/services/local_notification_service.dart';
import 'src/services/local_storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  
  // Initialize local storage with Hive (with error handling)
  try {
    await LocalStorageService.init();
    print('LocalStorageService inicializado correctamente');
  } catch (e) {
    debugPrint('Error inicializando LocalStorageService: $e');
    runApp(_StartupErrorApp(message: 'Storage startup failed: $e'));
    return;
  }

  try {
    await LocalNotificationService.initialize();
    await AppNotificationService.initialize();
    await GooglePayExpenseImportService.initialize();
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
    print('Error inicializando LocalStorageService: $e');
  }
  
  runApp(const SpendAntApp());
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF8B0000),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFFF176),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
