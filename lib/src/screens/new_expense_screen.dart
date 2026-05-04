import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/expense_draft.dart';
import '../models/expense_model.dart';
import '../services/app_analytics_service.dart';
import '../services/app_currency_format_service.dart';
import '../services/app_input_validation_service.dart';
import '../services/app_date_format_service.dart';
import '../services/app_time_format_service.dart';
import '../services/auto_categorization_service.dart';
import '../services/auth_memory_store.dart';
import '../services/cloudinary_receipt_upload_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/sync_log_service.dart';
import '../utils/url_utils.dart';
import '../services/expense_location_service.dart';
import '../services/local_storage_service.dart';
import '../services/platform_configuration_service.dart';
import '../services/receipt_scan_service.dart';
import '../services/connectivity_monitor.dart';
import '../theme/expense_visuals.dart';
import '../theme/spendant_theme.dart';
import '../mixins/connectivity_aware_mixin.dart';
import '../widgets/no_internet_banner.dart';
import '../widgets/spendant_delete_dialog.dart';

class _ExpenseLabelGroup {
  const _ExpenseLabelGroup({required this.label, required this.sublabels});

  final String label;
  final List<String> sublabels;
}

const List<_ExpenseLabelGroup> _expenseLabelGroups = <_ExpenseLabelGroup>[
  _ExpenseLabelGroup(
    label: 'Academic Essentials',
    sublabels: <String>['Commute', 'Learning Materials', 'University Fees'],
  ),
  _ExpenseLabelGroup(
    label: 'Lifestyle & Social',
    sublabels: <String>[
      'Entertainment',
      'Food',
      'Food Delivery',
      'Gifts',
      'Group Hangouts',
      'Subscriptions',
    ],
  ),
  _ExpenseLabelGroup(
    label: 'Living Expenses',
    sublabels: <String>[
      'Groceries',
      'Personal Care',
      'Rent',
      'Services',
      'Transport',
      'Utilities',
    ],
  ),
  _ExpenseLabelGroup(
    label: 'Strategic & Utility Tags',
    sublabels: <String>['Emergency', 'Impulse', 'Owed'],
  ),
];

enum _ReceiptSourceOption { camera, gallery, file }

class _ReceiptImportPayload {
  const _ReceiptImportPayload({
    required this.fileName,
    required this.bytes,
    this.path,
    this.lastModified,
  });

  final String fileName;
  final Uint8List bytes;
  final String? path;
  final DateTime? lastModified;
}

class NewExpenseScreen extends StatefulWidget {
  const NewExpenseScreen({
    super.key,
    this.initialDraft,
    this.editingExpense,
    this.headerTitle = 'New Expense',
  });

  final ExpenseDraft? initialDraft;
  final ExpenseModel? editingExpense;
  final String headerTitle;

  @override
  State<NewExpenseScreen> createState() => _NewExpenseScreenState();
}

class _NewExpenseScreenState extends State<NewExpenseScreen> {
  // Cached once per app session — defaultTargetPlatform never changes at
  // runtime, so re-creating this on every build() or _pickTime() call is
  // wasteful (micro-opt: avoid unnecessary objects in build/lifecycle methods).
  static final _materialTextTheme = Typography.material2021(
    platform: defaultTargetPlatform,
  ).black;

  final TextEditingController _expenseNameController = TextEditingController();
  final TextEditingController _expenseValueController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final AutoCategorizationService _autoCategorizationService =
      AutoCategorizationService.instance;
  final ReceiptScanService _receiptScanService = ReceiptScanService();
  final CloudinaryReceiptUploadService _cloudinaryReceiptUploadService =
      CloudinaryReceiptUploadService();

  String? _selectedCategory;
  List<String> _selectedDetailLabels = <String>[];
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  ExpenseLocationSelection? _selectedLocation;
  _ReceiptImportPayload? _selectedReceiptPayload;
  String? _receiptImagePath;
  String? _receiptCloudinaryUrl;
  bool _isScanningReceipt = false;
  bool _isSavingExpense = false;
  bool _isDeletingExpense = false;
  bool _isExpenseRegretted = false;
  bool _selectedLabelsWereAutoAssigned = false;
  ReceiptScanResult? _lastReceiptScanResult;
  int get _currentUserId => AuthMemoryStore.currentUserIdOrGuest;

  @override
  void initState() {
    super.initState();
    _applyInitialDraft();
  }

  @override
  void dispose() {
    _receiptScanService.dispose();
    _expenseNameController.dispose();
    _expenseValueController.dispose();
    super.dispose();
  }

  void _applyInitialDraft() {
    final editingExpense = widget.editingExpense;
    if (editingExpense != null) {
      _hydrateFromEditingExpense(editingExpense);
      return;
    }

    final draft = widget.initialDraft;
    if (draft == null) {
      return;
    }

    _hydrateFromDraft(draft);
  }

  void _hydrateFromEditingExpense(ExpenseModel editingExpense) {
    try {
      _expenseNameController.text = editingExpense.name.trim();
      _expenseValueController.text = _formatAmountForInput(
        editingExpense.amount,
      );
      _selectedCategory = _normalizedOptionalText(
        editingExpense.primaryCategory,
      );
      _applySelectedLabels(_normalizedLabels(editingExpense.detailLabels));
      _selectedCategory ??= _normalizedOptionalText(
        editingExpense.primaryCategory,
      );
      _selectedDate = DateUtils.dateOnly(editingExpense.date);
      _selectedTime = _timeOfDayFromStoredValue(editingExpense.time);
      _selectedLocation = _buildLocationSelection(
        label: editingExpense.locationName,
        latitude: editingExpense.latitude,
        longitude: editingExpense.longitude,
      );
      _receiptImagePath = _normalizedOptionalText(
        editingExpense.receiptImagePath,
      );
      _receiptCloudinaryUrl = _normalizedOptionalText(
        editingExpense.receiptCloudinaryUrl,
      );
      if (_receiptCloudinaryUrl == null &&
          looksLikeRemoteUrl(_receiptImagePath)) {
        _receiptCloudinaryUrl = _receiptImagePath;
        _receiptImagePath = null;
      }
      _isExpenseRegretted = editingExpense.isRegretted;
    } catch (error, stackTrace) {
      debugPrint('Failed to hydrate expense editor: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _hydrateFromDraft(ExpenseDraft draft) {
    _expenseNameController.text = draft.name.trim();
    _expenseValueController.text = draft.amount.trim();
    _selectedCategory = _normalizedOptionalText(draft.primaryCategory);
    _applySelectedLabels(_normalizedLabels(draft.detailLabels));
    _selectedCategory ??= _normalizedOptionalText(draft.primaryCategory);
    _selectedDate = DateUtils.dateOnly(draft.date);
    _selectedTime = draft.time;
    _selectedLocation = _buildLocationSelection(
      label: draft.locationLabel,
      latitude: draft.latitude,
      longitude: draft.longitude,
    );
  }

  String _formatAmountForInput(double amount) {
    if (!amount.isFinite || amount <= 0) {
      return '';
    }

    return AppCurrencyFormatService.formatAmount(amount);
  }

  List<String> _normalizedLabels(Iterable<String> labels) {
    final normalized = <String>[];
    for (final label in labels) {
      final trimmed = label.trim();
      if (trimmed.isEmpty || normalized.contains(trimmed)) {
        continue;
      }
      normalized.add(trimmed);
    }

    return normalized;
  }

  String? _normalizedOptionalText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return trimmed;
  }

  TimeOfDay _timeOfDayFromStoredValue(String rawValue) {
    final parsedTime = AppTimeFormatService.parseHourMinute(rawValue);
    return TimeOfDay(
      hour: parsedTime.hour.clamp(0, 23),
      minute: parsedTime.minute.clamp(0, 59),
    );
  }

  ExpenseLocationSelection? _buildLocationSelection({
    required String? label,
    required double? latitude,
    required double? longitude,
  }) {
    final trimmedLabel = _normalizedOptionalText(label);
    final position = _safeLatLng(latitude, longitude);
    if (trimmedLabel == null && position == null) {
      return null;
    }

    return ExpenseLocationSelection(
      label:
          trimmedLabel ??
          ExpenseLocationService.formatCoordinates(
            position!.latitude,
            position.longitude,
          ),
      position: position,
    );
  }

  LatLng? _safeLatLng(double? latitude, double? longitude) {
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite) {
      return null;
    }

    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }

    return LatLng(latitude, longitude);
  }

  String? _derivePrimaryCategory(List<String> labels) {
    for (final label in labels) {
      final category = ExpenseVisuals.detailLabelPrimaryCategories[label];
      if (category != null) {
        return category;
      }
    }

    if (labels.isNotEmpty) {
      return 'Other';
    }

    return null;
  }

  void _applySelectedLabels(
    List<String> labels, {
    bool isAutoAssigned = false,
  }) {
    _selectedDetailLabels = labels;
    _selectedCategory = _derivePrimaryCategory(labels);
    _selectedLabelsWereAutoAssigned = isAutoAssigned && labels.isNotEmpty;
  }

  void _removeSelectedLabel(String label) {
    setState(() {
      final updated = List<String>.from(_selectedDetailLabels)..remove(label);
      _applySelectedLabels(updated);
    });
  }

  Future<void> _pickDate() async {
    final selected = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) => DateSelectionScreen(initialDate: _selectedDate),
      ),
    );

    if (selected != null) {
      setState(() {
        _selectedDate = selected;
      });
    }
  }

  Future<void> _pickTime() async {
    final materialTextTheme = _materialTextTheme;
    const timeDisplayHeight = 64 / 57;
    const timeInputHeight = 54 / 48;
    final timePickerTextTheme = Theme.of(context).textTheme.copyWith(
      displayLarge: materialTextTheme.displayLarge?.copyWith(
        fontSize: 57,
        height: timeDisplayHeight,
        color: AppPalette.ink,
      ),
      displayMedium: materialTextTheme.displayMedium?.copyWith(
        fontSize: 48,
        height: timeInputHeight,
        color: AppPalette.ink,
      ),
      labelMedium: materialTextTheme.labelMedium?.copyWith(
        color: AppPalette.fieldHint,
      ),
      bodyLarge: materialTextTheme.bodyLarge?.copyWith(color: AppPalette.ink),
    );
    final selected = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      helpText: 'Select time',
      cancelText: 'Cancel',
      confirmText: 'OK',
      builder: (context, child) {
        if (child == null) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            textTheme: timePickerTextTheme,
            colorScheme: theme.colorScheme.copyWith(
              primary: AppPalette.green,
              onPrimary: AppPalette.ink,
              surface: AppPalette.field,
              onSurface: AppPalette.ink,
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: AppPalette.field,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
              helpTextStyle: timePickerTextTheme.labelMedium,
              hourMinuteShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              hourMinuteColor: WidgetStateColor.resolveWith((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return AppPalette.field;
                }
                return const Color(0xFFD7F6DE);
              }),
              hourMinuteTextColor: WidgetStateColor.resolveWith((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return AppPalette.ink;
                }
                return AppPalette.green;
              }),
              dayPeriodShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFF7A7A7A), width: 0.8),
              ),
              dayPeriodColor: WidgetStateColor.resolveWith((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return const Color(0xFFF6D0DB);
                }
                return const Color(0xFFECE6F0);
              }),
              dayPeriodTextColor: WidgetStateColor.resolveWith((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return AppPalette.fieldHint;
                }
                return AppPalette.ink;
              }),
              dayPeriodTextStyle: timePickerTextTheme.labelMedium,
              timeSelectorSeparatorColor: const WidgetStatePropertyAll<Color?>(
                AppPalette.ink,
              ),
              dialBackgroundColor: Colors.white.withValues(alpha: 0.8),
              dialHandColor: AppPalette.green,
              dialTextColor: WidgetStateColor.resolveWith((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return AppPalette.ink;
              }),
              dialTextStyle: timePickerTextTheme.bodyLarge,
              entryModeIconColor: AppPalette.fieldHint,
              cancelButtonStyle: TextButton.styleFrom(
                foregroundColor: AppPalette.green,
                textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w800),
              ),
              confirmButtonStyle: TextButton.styleFrom(
                foregroundColor: AppPalette.green,
                textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w900),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 18,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppPalette.green,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          child: child,
        );
      },
    );

    if (selected != null) {
      setState(() {
        _selectedTime = selected;
      });
    }
  }

  Future<void> _showNoInternetDialog({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            decoration: BoxDecoration(
              color: AppPalette.field,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.fieldHint,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'OK',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickLocation() async {
    if (!ConnectivityMonitor.isOnline) {
      await _showNoInternetDialog(
        title: 'No internet connection',
        message:
            'The map view requires internet. Please connect to the internet to pick a location.',
      );
      return;
    }

    final selected = await Navigator.of(context).push<ExpenseLocationSelection>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initialValue: _selectedLocation),
      ),
    );

    if (selected != null) {
      setState(() {
        _selectedLocation = selected;
      });
    }
  }

  Future<void> _pickLabels() async {
    final selected = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) =>
            LabelSelectionScreen(initialSelection: _selectedDetailLabels),
      ),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _applySelectedLabels(selected);
    });
  }

  Future<void> _scanReceipt() async {
    final source = await _showReceiptSourceSheet();
    if (source == null) {
      return;
    }

    final hasPermission = await _ensureReceiptPermission(source);
    if (!hasPermission) {
      return;
    }

    final payload = await _pickReceiptPayload(source);
    if (payload == null) {
      return;
    }

    setState(() {
      _selectedReceiptPayload = payload;
      _receiptImagePath = payload.path;
      _receiptCloudinaryUrl = null;
      _isScanningReceipt = true;
    });

    try {
      final result = await _receiptScanService.scanReceipt(
        fileName: payload.fileName,
        bytes: payload.bytes,
        path: payload.path,
        fallbackTimestamp: payload.lastModified,
      );

      if (!mounted) {
        return;
      }

      _applyReceiptScanResult(result);
      _showScanMessage(
        result.hasDetectedData
            ? 'Receipt scanned. Review the detected fields before saving.'
            : 'No clear receipt data was detected from that file.',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showScanMessage(
        'The selected receipt could not be processed. Try a clearer image or another file.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isScanningReceipt = false;
        });
      }
    }
  }

  Future<_ReceiptSourceOption?> _showReceiptSourceSheet() {
    return showModalBottomSheet<_ReceiptSourceOption>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ReceiptSourceSheet(
          onSelected: (source) => Navigator.of(context).pop(source),
        );
      },
    );
  }

  Future<_ReceiptImportPayload?> _pickReceiptPayload(
    _ReceiptSourceOption source,
  ) async {
    switch (source) {
      case _ReceiptSourceOption.camera:
        if (kIsWeb ||
            (defaultTargetPlatform != TargetPlatform.android &&
                defaultTargetPlatform != TargetPlatform.iOS)) {
          _showScanMessage(
            'Camera capture is only available on phones. Use Gallery or File instead.',
          );
          return null;
        }

        final image = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 88,
        );
        if (image == null) {
          return null;
        }
        return _ReceiptImportPayload(
          fileName: image.name,
          path: image.path,
          bytes: await image.readAsBytes(),
          lastModified: await image.lastModified(),
        );
      case _ReceiptSourceOption.gallery:
        final image = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
        );
        if (image == null) {
          return null;
        }
        return _ReceiptImportPayload(
          fileName: image.name,
          path: image.path,
          bytes: await image.readAsBytes(),
          lastModified: await image.lastModified(),
        );
      case _ReceiptSourceOption.file:
        final file = await FilePicker.platform.pickFiles(
          allowMultiple: false,
          withData: true,
          type: FileType.custom,
          allowedExtensions: <String>[
            'pdf',
            'png',
            'jpg',
            'jpeg',
            'webp',
            'heic',
            'heif',
          ],
        );
        if (file == null || file.files.isEmpty) {
          return null;
        }

        final selectedFile = file.files.single;
        final bytes = selectedFile.bytes;
        if (bytes == null) {
          _showScanMessage('The selected file could not be opened.');
          return null;
        }

        return _ReceiptImportPayload(
          fileName: selectedFile.name,
          path: selectedFile.path,
          bytes: bytes,
        );
    }
  }

  Future<bool> _ensureReceiptPermission(_ReceiptSourceOption source) async {
    switch (source) {
      case _ReceiptSourceOption.camera:
        if (kIsWeb ||
            (defaultTargetPlatform != TargetPlatform.android &&
                defaultTargetPlatform != TargetPlatform.iOS)) {
          _showScanMessage(
            'Camera capture is only available on phones. Use Gallery or File instead.',
          );
          return false;
        }

        final status = await Permission.camera.request();
        return _handlePermissionStatus(
          status,
          deniedMessage:
              'Camera permission is required to capture a receipt photo.',
        );
      case _ReceiptSourceOption.gallery:
        if (defaultTargetPlatform == TargetPlatform.android) {
          final photoStatus = await Permission.photos.request();
          if (photoStatus.isGranted || photoStatus.isLimited) {
            return true;
          }

          final storageStatus = await Permission.storage.request();
          return _handlePermissionStatus(
            storageStatus,
            deniedMessage:
                'Photos permission is required to pick a receipt from the gallery.',
          );
        }

        final status = await Permission.photos.request();
        return _handlePermissionStatus(
          status,
          deniedMessage:
              'Photos permission is required to pick a receipt from the gallery.',
        );
      case _ReceiptSourceOption.file:
        if (defaultTargetPlatform == TargetPlatform.android) {
          final manageStatus = await Permission.manageExternalStorage.request();
          if (manageStatus.isGranted) {
            return true;
          }

          final storageStatus = await Permission.storage.request();
          return _handlePermissionStatus(
            storageStatus,
            deniedMessage:
                'Files permission is required to import a receipt document.',
          );
        }

        if (defaultTargetPlatform == TargetPlatform.iOS) {
          _showScanMessage(
            'iOS does not expose a separate Files permission. The document picker will open directly.',
          );
        }
        return true;
    }
  }

  Future<bool> _handlePermissionStatus(
    PermissionStatus status, {
    required String deniedMessage,
  }) async {
    if (status.isGranted || status.isLimited) {
      return true;
    }

    if (status.isPermanentlyDenied || status.isRestricted) {
      _showScanMessage('$deniedMessage Open app settings to enable it.');
      await openAppSettings();
      return false;
    }

    _showScanMessage(deniedMessage);
    return false;
  }

  void _applyReceiptScanResult(ReceiptScanResult result) {
    setState(() {
      _lastReceiptScanResult = result;

      if (result.name != null && result.name!.trim().isNotEmpty) {
        _expenseNameController.text = result.name!.trim();
      }

      if (result.formattedAmount != null &&
          result.formattedAmount!.trim().isNotEmpty) {
        _expenseValueController.text = result.formattedAmount!.trim();
      }

      if (result.date != null) {
        _selectedDate = result.date!;
      }

      if (result.time != null) {
        _selectedTime = TimeOfDay.fromDateTime(result.time!);
      }

      if (result.location != null) {
        _selectedLocation = ExpenseLocationSelection(
          label: result.location!.label,
          position:
              result.location!.latitude != null &&
                  result.location!.longitude != null
              ? LatLng(result.location!.latitude!, result.location!.longitude!)
              : null,
        );
      }
    });
  }

  Future<String?> _resolveReceiptCloudinaryUrl() async {
    // Case 1: no new receipt selected — return whatever URL is already stored.
    // This covers both existing remote URLs and legacy local-path-as-URL records.
    if (_selectedReceiptPayload == null) {
      return _effectiveReceiptCloudinaryUrl;
    }

    // Case 2: a new receipt was selected but already uploaded during this
    // editing session — reuse the cached URL to avoid a duplicate upload.
    if (_receiptCloudinaryUrl != null) {
      return _receiptCloudinaryUrl;
    }

    // Case 3: new receipt selected and not yet uploaded — upload now.
    final payload = _selectedReceiptPayload!;
    try {
      final uploadedUrl = await _cloudinaryReceiptUploadService.uploadReceipt(
        userId: _currentUserId,
        fileName: payload.fileName,
        bytes: payload.bytes,
      );
      _receiptCloudinaryUrl = uploadedUrl;
      return uploadedUrl;
    } catch (error) {
      // Upload failed — the expense is saved without a cloud receipt URL.
      // The local file path (if any) remains accessible on this device.
      debugPrint('Cloudinary receipt upload failed: $error');
      unawaited(SyncLogService.logSync(
        entityType: SyncLogService.entityExpense,
        entityId: null,
        action: SyncLogService.actionUpload,
        success: false,
        errorMessage: 'Cloudinary receipt upload failed: $error',
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Receipt saved locally. Cloud backup unavailable right now.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return null;
    }
  }

  String? get _effectiveReceiptCloudinaryUrl {
    final normalizedCloudinaryUrl = _normalizedOptionalText(
      _receiptCloudinaryUrl,
    );
    if (normalizedCloudinaryUrl != null) {
      return normalizedCloudinaryUrl;
    }

    final normalizedReceiptImagePath = _normalizedOptionalText(
      _receiptImagePath,
    );
    if (looksLikeRemoteUrl(normalizedReceiptImagePath)) {
      return normalizedReceiptImagePath;
    }

    return null;
  }

  String? get _effectiveLocalReceiptImagePath {
    final normalizedReceiptImagePath = _normalizedOptionalText(
      _receiptImagePath,
    );
    if (looksLikeRemoteUrl(normalizedReceiptImagePath)) {
      return null;
    }

    return normalizedReceiptImagePath;
  }

  void _showScanMessage(String message) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _tryAutoCategorizeBeforeSave(String expenseName) async {
    if (_selectedDetailLabels.isNotEmpty || expenseName.trim().isEmpty) {
      return;
    }

    if (!ConnectivityMonitor.isOnline) {
      // Offline: fall through to _showMissingLabelWarning so the user gets
      // a single, actionable prompt instead of two sequential dialogs.
      return;
    }

    final result = await _autoCategorizationService.categorizeExpense(
      expenseName,
    );
    if (!mounted || !result.assigned) {
      return;
    }

    setState(() {
      _applySelectedLabels(
        List<String>.from(result.detailLabels),
        isAutoAssigned: true,
      );
    });
  }

  bool _shouldLearnFromManualCategory(ExpenseModel? editingExpense) {
    if (_selectedLabelsWereAutoAssigned || _selectedDetailLabels.isEmpty) {
      return false;
    }

    if (editingExpense == null) {
      return true;
    }

    final hadExistingLabels = editingExpense.detailLabels.any(
      (label) => label.trim().isNotEmpty,
    );
    return editingExpense.isPendingCategory || !hadExistingLabels;
  }

  void _syncPendingDataInBackground() {
    unawaited(_runPendingCloudSync());
  }

  Future<void> _runPendingCloudSync() async {
    try {
      await CloudSyncService().syncAllPendingData();
    } catch (_) {
      // Keep the local save as the source of truth and retry cloud sync later.
    }
  }

  Future<void> _deleteEditingExpense() async {
    final editingExpense = widget.editingExpense;
    if (editingExpense == null || _isDeletingExpense || _isSavingExpense) {
      return;
    }

    FocusScope.of(context).unfocus();

    final shouldDelete = await showSpendAntDeleteDialog(
      context,
      title: 'Delete expense?',
      name: editingExpense.name,
      confirmLabel: 'Delete',
    );
    if (!shouldDelete || !mounted) {
      return;
    }

    setState(() {
      _isDeletingExpense = true;
    });

    try {
      final deletedFromCloud = await CloudSyncService().deleteExpenseRecord(
        editingExpense,
      );
      if (!mounted) {
        return;
      }

      if (!deletedFromCloud) {
        await _showDeleteOutcomeMessage(
          'Expense deleted locally. The cloud copy could not be removed right now.',
        );
        if (!mounted) {
          return;
        }
      }

      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isDeletingExpense = false;
      });
      await _showDeleteOutcomeMessage('The expense could not be deleted.');
    }
  }

  Future<void> _showDeleteOutcomeMessage(String message) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleConfirm() async {
    if (_isSavingExpense || _isDeletingExpense) {
      return;
    }

    FocusScope.of(context).unfocus();

    // Validate required fields
    final expenseName = _expenseNameController.text.trim();
    if (expenseName.isEmpty) {
      _showScanMessage('Please enter an expense name');
      return;
    }
    if (AppInputValidationService.isOnlyEmoji(expenseName)) {
      _showScanMessage('Expense name must contain some text, not only emojis');
      return;
    }

    final amountText = _expenseValueController.text.replaceAll(',', '').trim();
    final parsedAmount = double.tryParse(amountText);
    if (amountText.isEmpty || parsedAmount == null || parsedAmount <= 0) {
      _showScanMessage('Please enter a valid amount');
      return;
    }

    if (_selectedDetailLabels.isEmpty) {
      await _tryAutoCategorizeBeforeSave(expenseName);
    }

    if (_selectedDetailLabels.isEmpty) {
      await _showMissingLabelWarning();
      return;
    }

    _selectedCategory ??=
        _derivePrimaryCategory(_selectedDetailLabels) ?? 'Other';

    setState(() {
      _isSavingExpense = true;
    });

    final editingExpense = widget.editingExpense;
    final shouldLearnFromManualCategory = _shouldLearnFromManualCategory(
      editingExpense,
    );
    final wasAutoCategorized =
        _selectedLabelsWereAutoAssigned ||
        (editingExpense?.wasAutoCategorized ?? false);
    final expense = editingExpense ?? ExpenseModel();
    final receiptCloudinaryUrl = await _resolveReceiptCloudinaryUrl();

    // Guard: user may have closed the screen while the receipt upload was running.
    if (!mounted) {
      return;
    }

    final receiptImagePath = _effectiveLocalReceiptImagePath;
    final normalizedLocationLabel = _normalizedOptionalText(
      _selectedLocation?.label,
    );

    expense
      ..userId = editingExpense?.userId ?? _currentUserId
      ..name = expenseName
      ..amount = parsedAmount
      ..date = _selectedDate
      ..time =
          '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}'
      ..latitude = _selectedLocation?.position?.latitude
      ..longitude = _selectedLocation?.position?.longitude
      ..locationName = normalizedLocationLabel
      ..source = (editingExpense?.source.trim().isNotEmpty ?? false)
          ? editingExpense!.source
          : (_lastReceiptScanResult != null ? 'OCR' : 'MANUAL')
      ..receiptImagePath = receiptImagePath
      ..receiptCloudinaryUrl = receiptCloudinaryUrl
      ..isRegretted = _isExpenseRegretted
      ..isPendingCategory = false
      ..isRecurring = editingExpense?.isRecurring ?? false
      ..recurrenceInterval = editingExpense?.recurrenceInterval
      ..recurrenceUnit = editingExpense?.recurrenceUnit
      ..nextOccurrenceDate = editingExpense?.nextOccurrenceDate
      ..isSynced = false
      ..serverId = editingExpense?.serverId
      ..createdAt = editingExpense?.createdAt ?? DateTime.now()
      ..primaryCategory = _selectedCategory
      ..detailLabels = List<String>.from(_selectedDetailLabels)
      ..wasAutoCategorized = wasAutoCategorized;

    try {
      if (editingExpense == null) {
        await LocalStorageService().saveExpense(expense);
      } else if (editingExpense.isInBox) {
        await expense.save();
      } else {
        throw StateError(
          'The selected expense is no longer attached to local storage.',
        );
      }
    } catch (e) {
      unawaited(AppAnalyticsService.instance.logModuleCrash('expenses', e));
      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingExpense = false;
      });
      _showScanMessage('The expense could not be saved');
      return;
    }

    if (!mounted) {
      return;
    }

    if (shouldLearnFromManualCategory) {
      final labelToLearn = _selectedDetailLabels.first;
      unawaited(
        _autoCategorizationService.learnFromManualCategory(
          merchantText: expense.name,
          label: labelToLearn,
        ),
      );
    }

    final navigator = Navigator.of(context);
    navigator.pop(true);
    _syncPendingDataInBackground();
  }

  Future<void> _showMissingLabelWarning() {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            decoration: BoxDecoration(
              color: AppPalette.field,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Where does this one go?',
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  ConnectivityMonitor.isOnline
                      ? "I don't recognize this expense yet. Give it a label so I can learn for next time."
                      : "Auto-categorization needs internet. Select a label manually to save.",
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.fieldHint,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Continue',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final formBottomPadding = 116.0 + keyboardInset;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            top: false,
            child: Column(
              children: [
                _ExpenseHeader(
                  title: widget.headerTitle,
                  isSubmitting: _isSavingExpense || _isDeletingExpense,
                  onClose: () => Navigator.of(context).maybePop(),
                  onConfirm: () {
                    _handleConfirm();
                  },
                ),
                const NoInternetBanner(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final centeredMinHeight = math.max(
                        0.0,
                        constraints.maxHeight - formBottomPadding,
                      );

                      return SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          24,
                          24,
                          24,
                          formBottomPadding,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: centeredMinHeight,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _ExpenseField(
                                    controller: _expenseNameController,
                                    hintText: 'Expense name',
                                  ),
                                  const SizedBox(height: 22),
                                  _ExpenseField(
                                    controller: _expenseValueController,
                                    hintText: r'$ 0',
                                    keyboardType: TextInputType.number,
                                    inputFormatters: const [
                                      _CurrencyThousandsFormatter(),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: InkWell(
                                      onTap:
                                          _isSavingExpense || _isDeletingExpense
                                          ? null
                                          : () {
                                              setState(() {
                                                _isExpenseRegretted =
                                                    !_isExpenseRegretted;
                                              });
                                            },
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: Checkbox(
                                                value: _isExpenseRegretted,
                                                onChanged:
                                                    _isSavingExpense ||
                                                        _isDeletingExpense
                                                    ? null
                                                    : (value) {
                                                        setState(() {
                                                          _isExpenseRegretted =
                                                              value ?? false;
                                                        });
                                                      },
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                visualDensity:
                                                    VisualDensity.compact,
                                                side: const BorderSide(
                                                  color: AppPalette.ink,
                                                  width: 1.2,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Do you regret this expense?',
                                              style: GoogleFonts.nunito(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: AppPalette.ink,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Wrap(
                                    alignment: WrapAlignment.start,
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      _MiniActionButton(
                                        icon: Icons.add,
                                        label: 'Label',
                                        onPressed: _pickLabels,
                                      ),
                                      for (final label in _selectedDetailLabels)
                                        _SelectedExpenseLabelChip(
                                          label: label,
                                          onTap: () =>
                                              _removeSelectedLabel(label),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  Center(
                                    child: SizedBox(
                                      width: 148,
                                      child: widget.editingExpense == null
                                          ? ElevatedButton.icon(
                                              onPressed: _isScanningReceipt
                                                  ? null
                                                  : _scanReceipt,
                                              icon: _isScanningReceipt
                                                  ? const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        valueColor:
                                                            AlwaysStoppedAnimation<
                                                              Color
                                                            >(AppPalette.white),
                                                      ),
                                                    )
                                                  : SvgPicture.asset(
                                                      'web/icons/Camera.svg',
                                                      width: 18,
                                                      height: 18,
                                                      colorFilter:
                                                          const ColorFilter.mode(
                                                            AppPalette.white,
                                                            BlendMode.srcIn,
                                                          ),
                                                    ),
                                              label: Text(
                                                _isScanningReceipt
                                                    ? 'Scanning...'
                                                    : 'Scan Receipt',
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                      horizontal: 14,
                                                    ),
                                                textStyle: GoogleFonts.nunito(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            )
                                          : ElevatedButton(
                                              onPressed:
                                                  _isDeletingExpense ||
                                                      _isSavingExpense
                                                  ? null
                                                  : _deleteEditingExpense,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppPalette.ink,
                                                foregroundColor:
                                                    AppPalette.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 14,
                                                      horizontal: 14,
                                                    ),
                                                textStyle: GoogleFonts.nunito(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                              child: Text(
                                                _isDeletingExpense
                                                    ? 'Deleting...'
                                                    : 'Delete Expense',
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            bottom: keyboardInset,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.black12)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _MetaChip(
                        icon: Icons.calendar_today_outlined,
                        label: AppDateFormatService.longDate(_selectedDate),
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MetaChip(
                        icon: Icons.access_time,
                        label: _selectedTime.format(context).toLowerCase(),
                        onTap: _pickTime,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MetaChip(
                        icon: Icons.location_on_outlined,
                        label: _selectedLocation?.label ?? 'Pick location',
                        onTap: _pickLocation,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ExpenseLocationSelection {
  const ExpenseLocationSelection({required this.label, this.position});

  final String label;
  final LatLng? position;
}

// ─────────────────────────────────────────────────────────
// MOCK RECEIPT SCANNER (web / demo)
// ─────────────────────────────────────────────────────────

class _MockReceiptScannerScreen extends StatefulWidget {
  const _MockReceiptScannerScreen();

  @override
  State<_MockReceiptScannerScreen> createState() =>
      _MockReceiptScannerScreenState();
}

class _MockReceiptScannerScreenState extends State<_MockReceiptScannerScreen> {
  bool _scanning = false;

  static final ReceiptScanResult _mockResult = ReceiptScanResult(
    name: 'Ajiaco y Frijoles Centro Histórico',
    formattedAmount: '25,020',
    date: DateTime(2026, 3, 19),
    time: DateTime(2026, 3, 19, 13, 45),
    location: const ReceiptScanLocation(label: 'Calle 20 #6-76, Bogotá'),
    rawText: '',
  );

  Future<void> _capture() async {
    setState(() => _scanning = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    Navigator.of(context).pop(_mockResult);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: AppPalette.green,
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppPalette.ink),
                  ),
                  Expanded(
                    child: Text(
                      'New Receipt',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // Viewfinder
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Camera background
                  Container(color: const Color(0xFF2A1F1A)),

                  // Mock receipt in center
                  Center(
                    child: Transform.rotate(
                      angle: -0.03,
                      child: Container(
                        width: 220,
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black45,
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'AJIACO Y FRIJOLES\nCENTRO HISTÓRICO SAS',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunito(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'NIT: 902619477-5\nCalle 20 #6-76, Bogotá',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunito(
                                fontSize: 8,
                                color: Colors.black54,
                              ),
                            ),
                            const Divider(height: 16),
                            _MockReceiptRow('Ajiaco Mix', '22,900'),
                            const Divider(height: 12),
                            _MockReceiptRow('Total bruto', '21,201.70'),
                            _MockReceiptRow('Impoconsumo 8%', '1,698.57'),
                            _MockReceiptRow('Propina vol.', '2,120.37'),
                            const Divider(height: 12),
                            _MockReceiptRow(
                              'Total a pagar:',
                              '25,020.37',
                              bold: true,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Fecha: 19/03/2026  13:45',
                              style: GoogleFonts.nunito(
                                fontSize: 7,
                                color: Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Scanning overlay
                  if (_scanning)
                    Container(
                      color: Colors.white.withValues(alpha: 0.15),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: AppPalette.green,
                          strokeWidth: 3,
                        ),
                      ),
                    ),

                  // Corner guides
                  Positioned(top: 60, left: 40, child: _CornerGuide(rotate: 0)),
                  Positioned(
                    top: 60,
                    right: 40,
                    child: _CornerGuide(rotate: 1),
                  ),
                  Positioned(
                    bottom: 30,
                    left: 40,
                    child: _CornerGuide(rotate: 3),
                  ),
                  Positioned(
                    bottom: 30,
                    right: 40,
                    child: _CornerGuide(rotate: 2),
                  ),
                ],
              ),
            ),

            // Bottom action bar
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CameraActionButton(
                    icon: Icons.photo_library,
                    onTap: _scanning ? null : _capture,
                  ),
                  // Shutter button (main)
                  GestureDetector(
                    onTap: _scanning ? null : _capture,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: const BoxDecoration(
                        color: AppPalette.green,
                        shape: BoxShape.circle,
                      ),
                      child: _scanning
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt,
                              color: AppPalette.ink,
                              size: 32,
                            ),
                    ),
                  ),
                  _CameraActionButton(
                    icon: Icons.file_copy,
                    onTap: _scanning ? null : _capture,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MockReceiptRow extends StatelessWidget {
  const _MockReceiptRow(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.nunito(
      fontSize: bold ? 9 : 8,
      fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
      color: Colors.black,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _CornerGuide extends StatelessWidget {
  const _CornerGuide({required this.rotate});

  final int rotate;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotate * 3.14159 / 2,
      child: SizedBox(
        width: 28,
        height: 28,
        child: CustomPaint(painter: _CornerPainter()),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppPalette.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CameraActionButton extends StatelessWidget {
  const _CameraActionButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(
          color: AppPalette.green,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppPalette.ink, size: 24),
      ),
    );
  }
}

class _ReceiptSourceSheet extends StatelessWidget {
  const _ReceiptSourceSheet({required this.onSelected});

  final ValueChanged<_ReceiptSourceOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF6D6D6D),
                borderRadius: AppRadius.pill,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'New Receipt',
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppPalette.ink,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ReceiptSourceTile(
                  icon: Icons.photo_camera,
                  label: 'Camera',
                  onTap: () => onSelected(_ReceiptSourceOption.camera),
                ),
                _ReceiptSourceTile(
                  icon: Icons.image,
                  label: 'Gallery',
                  onTap: () => onSelected(_ReceiptSourceOption.gallery),
                ),
                _ReceiptSourceTile(
                  icon: Icons.file_copy,
                  label: 'File',
                  onTap: () => onSelected(_ReceiptSourceOption.file),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptSourceTile extends StatelessWidget {
  const _ReceiptSourceTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppPalette.green,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: AppPalette.ink),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppPalette.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DateSelectionScreen extends StatefulWidget {
  const DateSelectionScreen({
    super.key,
    required this.initialDate,
    this.minDate,
  });

  final DateTime initialDate;

  /// When set, the calendar will not allow selecting a date before this day.
  /// Defaults to 2020-01-01 (allows past dates, used for expense editing).
  final DateTime? minDate;

  @override
  State<DateSelectionScreen> createState() => _DateSelectionScreenState();
}

class _DateSelectionScreenState extends State<DateSelectionScreen> {
  static final _materialTextTheme = Typography.material2021(
    platform: defaultTargetPlatform,
  ).black;

  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(widget.initialDate);
    final effectiveMin = widget.minDate != null
        ? DateUtils.dateOnly(widget.minDate!)
        : null;
    // Clamp initialDate to minDate so the calendar never starts in a blocked range.
    _selectedDate = effectiveMin != null && today.isBefore(effectiveMin)
        ? effectiveMin
        : today;
  }

  @override
  Widget build(BuildContext context) {
    final materialTextTheme = _materialTextTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _ExpenseHeader(
              isSubmitting: false,
              title: 'New Expense',
              onClose: () => Navigator.of(context).pop(),
              onConfirm: () => Navigator.of(context).pop(_selectedDate),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  decoration: BoxDecoration(
                    color: AppPalette.field,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select date',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.fieldHint,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        DateFormat('EEE, MMM d').format(_selectedDate),
                        style: materialTextTheme.displayLarge?.copyWith(
                          fontSize: 32,
                          height: 40 / 32,
                          color: AppPalette.ink,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: CalendarDatePicker(
                          initialDate: _selectedDate,
                          firstDate: widget.minDate != null
                              ? DateUtils.dateOnly(widget.minDate!)
                              : DateTime(2020),
                          lastDate: DateTime(2040),
                          currentDate: DateTime.now(),
                          onDateChanged: (value) {
                            setState(() {
                              _selectedDate = value;
                            });
                          },
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Close',
                              style: GoogleFonts.nunito(
                                fontWeight: FontWeight.w800,
                                color: AppPalette.green,
                              ),
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.nunito(
                                fontWeight: FontWeight.w800,
                                color: AppPalette.green,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.of(context).pop(_selectedDate),
                            child: Text(
                              'OK',
                              style: GoogleFonts.nunito(
                                fontWeight: FontWeight.w900,
                                color: AppPalette.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initialValue});

  final ExpenseLocationSelection? initialValue;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen>
    with ConnectivityAwareStateMixin<LocationPickerScreen> {
  static const LatLng _defaultCenter = LatLng(4.60971, -74.08175);

  final ExpenseLocationService _locationService =
      const ExpenseLocationService();
  late final Future<bool> _hasGoogleMapsApiKeyFuture =
      PlatformConfigurationService.ensureGoogleMapsIsReady();
  final TextEditingController _searchController = TextEditingController();

  GoogleMapController? _mapController;
  LatLng? _selectedPoint;
  String? _resolvedLabel;
  bool _isFetchingCurrentLocation = false;
  bool _isSearchingLocation = false;
  bool _isResolvingLocation = false;
  String? _statusMessage;
  int _selectionRequestId = 0;
  bool _isOffline = !ConnectivityMonitor.isOnline;

  bool get _canSave {
    return _selectedPoint != null ||
        _searchController.text.trim().isNotEmpty ||
        (_resolvedLabel?.trim().isNotEmpty ?? false);
  }

  String get _selectionLabel {
    final typedLabel = _searchController.text.trim();
    if (typedLabel.isNotEmpty) {
      return typedLabel;
    }

    final resolvedLabel = _resolvedLabel?.trim();
    if (resolvedLabel != null && resolvedLabel.isNotEmpty) {
      return resolvedLabel;
    }

    final point = _selectedPoint;
    if (point != null) {
      return ExpenseLocationService.formatCoordinates(
        point.latitude,
        point.longitude,
      );
    }

    return '';
  }

  LatLng get _cameraTarget => _selectedPoint ?? _defaultCenter;

  @override
  void onConnectivityChanged({required bool isOnline}) {
    setState(() => _isOffline = !isOnline);
    if (!isOnline) {
      unawaited(_showOfflineAndExit());
    }
  }

  Future<void> _showOfflineAndExit() async {
    await _showOfflineMapDialog();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showOfflineMapDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            decoration: BoxDecoration(
              color: AppPalette.field,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No internet connection',
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Map functionality has been disabled because there is no internet connection available.',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.fieldHint,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'OK',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();

    _selectedPoint = widget.initialValue?.position;

    final initialLabel = widget.initialValue?.label.trim();
    _resolvedLabel = initialLabel != null && initialLabel.isNotEmpty
        ? initialLabel
        : null;
    _searchController.text = _resolvedLabel ?? '';

    if (_selectedPoint != null &&
        (_resolvedLabel == null ||
            ExpenseLocationService.looksLikeCoordinateLabel(_resolvedLabel!))) {
      unawaited(_refreshSelectionLabel(syncSearchField: true));
    } else if (_selectedPoint == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_prefillCurrentLocationIfAvailable());
      });
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _ExpenseHeader(
              isSubmitting: _isOffline,
              title: 'Pick Location',
              onClose: () => Navigator.of(context).pop(),
              onConfirm: _submitSelection,
            ),
            const NoInternetBanner(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) {
                        setState(() {
                          _statusMessage = null;
                        });
                      },
                      onSubmitted: (_) => _searchLocation(),
                      decoration: InputDecoration(
                        hintText: 'Search place or address',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _isSearchingLocation
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: AppPalette.green,
                                  ),
                                ),
                              )
                            : IconButton(
                                onPressed: _searchLocation,
                                icon: const Icon(Icons.arrow_forward_rounded),
                              ),
                        fillColor: Colors.white,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: AppRadius.pill,
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _isFetchingCurrentLocation
                              ? null
                              : _useCurrentLocation,
                          icon: _isFetchingCurrentLocation
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppPalette.green,
                                  ),
                                )
                              : const Icon(Icons.my_location_rounded, size: 18),
                          label: Text(
                            _isFetchingCurrentLocation
                                ? 'Locating...'
                                : 'Use current location',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppPalette.green,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _helperText,
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF4E4E4E),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          color: AppPalette.field,
                          child: Stack(
                            children: [
                              Positioned.fill(child: _buildMapSurface()),
                              Positioned(
                                left: 16,
                                right: 16,
                                bottom: 16,
                                child: _LocationPickerFooter(
                                  label: _selectionLabel,
                                  onSave: _canSave ? _submitSelection : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapSurface() {
    return FutureBuilder<bool>(
      future: _hasGoogleMapsApiKeyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: AppPalette.green),
          );
        }

        if (snapshot.data != true) {
          return _buildMapFallback(
            kIsWeb
                ? 'Google Maps on web is unavailable right now. You can still use search, type a place name, or save your current location. For local debug, open the app once with ?gmapsKey=YOUR_KEY.'
                : 'Google Maps needs a configured native API key on this app. The map is blocked until that key is present, but you can still search, type a place name, and save the location.',
          );
        }

        return GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _cameraTarget,
            zoom: 16,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
          },
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onTap: _selectPoint,
          markers: _selectedPoint == null
              ? const <Marker>{}
              : <Marker>{
                  Marker(
                    markerId: const MarkerId('selected-location'),
                    position: _selectedPoint!,
                    infoWindow: InfoWindow(title: _selectionLabel),
                  ),
                },
        );
      },
    );
  }

  Widget _buildMapFallback(String message) {
    return Container(
      color: const Color(0xFFEDEDED),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.nunito(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppPalette.ink,
        ),
      ),
    );
  }

  String get _helperText {
    final label = _selectionLabel;
    final point = _selectedPoint;

    if (_isFetchingCurrentLocation) {
      return 'Detecting your current location...';
    }

    if (_isSearchingLocation) {
      return label.isNotEmpty ? 'Searching for "$label"...' : 'Searching...';
    }

    if (_isResolvingLocation) {
      return 'Resolving the selected point...';
    }

    if (point == null) {
      if (label.isNotEmpty) {
        if (_statusMessage != null && _statusMessage!.trim().isNotEmpty) {
          return '$label\n${_statusMessage!}';
        }
        return label;
      }

      if (_statusMessage != null) {
        return _statusMessage!;
      }

      return 'Search a place, use your current location, or tap the map to pin where the expense happened.';
    }

    final coordinates = ExpenseLocationService.formatCoordinates(
      point.latitude,
      point.longitude,
    );

    if (label.isEmpty ||
        ExpenseLocationService.looksLikeCoordinateLabel(label)) {
      if (_statusMessage != null && _statusMessage!.trim().isNotEmpty) {
        return '$coordinates\n${_statusMessage!}';
      }
      return coordinates;
    }

    if (_statusMessage != null && _statusMessage!.trim().isNotEmpty) {
      return '$label - $coordinates\n${_statusMessage!}';
    }

    return '$label - $coordinates';
  }

  Future<void> _searchLocation() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _showLocationMessage('Type a place or address first.');
      return;
    }

    // Fast-path: skip the network call and save the typed name immediately.
    if (_isOffline) {
      FocusScope.of(context).unfocus();
      setState(() {
        _resolvedLabel = query;
        _statusMessage =
            'Location search needs internet. Your place name has been saved.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    final requestId = ++_selectionRequestId;

    setState(() {
      _isSearchingLocation = true;
      _isResolvingLocation = false;
      _statusMessage = null;
    });

    final result = await _locationService.search(query);
    if (!mounted || requestId != _selectionRequestId) {
      return;
    }

    if (result == null) {
      setState(() {
        _isSearchingLocation = false;
        _isResolvingLocation = false;
        _resolvedLabel = query;
        _statusMessage =
            'Using the typed place name. Add your current location or a pin if you want coordinates too.';
      });
      return;
    }

    final point = LatLng(result.latitude, result.longitude);

    setState(() {
      _isSearchingLocation = false;
      _isResolvingLocation = false;
      _selectedPoint = point;
      _resolvedLabel = result.label;
      _statusMessage = 'Search matched this place.';
    });

    _replaceSearchText(result.label);
    await _moveCamera(point);
  }

  Future<void> _prefillCurrentLocationIfAvailable() async {
    if (!mounted || _selectedPoint != null) {
      return;
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted || _selectedPoint != null) {
        return;
      }

      final point = LatLng(position.latitude, position.longitude);
      final previousAutoLabel = _resolvedLabel;
      final provisionalLabel = ExpenseLocationService.formatCoordinates(
        point.latitude,
        point.longitude,
      );
      final requestId = ++_selectionRequestId;

      setState(() {
        _selectedPoint = point;
        _resolvedLabel = provisionalLabel;
        _isResolvingLocation = true;
        _statusMessage = 'Using your current location.';
      });

      if (_shouldSyncSearchField(previousAutoLabel, provisionalLabel)) {
        _replaceSearchText(provisionalLabel);
      }

      await _moveCamera(point);

      final resolvedLabel = await _locationService.resolveLabel(
        latitude: point.latitude,
        longitude: point.longitude,
      );
      if (!mounted || requestId != _selectionRequestId) {
        return;
      }

      setState(() {
        _resolvedLabel = resolvedLabel;
        _isResolvingLocation = false;
        _statusMessage = 'Using your current location.';
      });

      if (_shouldSyncSearchField(previousAutoLabel, provisionalLabel)) {
        _replaceSearchText(resolvedLabel);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isResolvingLocation = false;
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _isFetchingCurrentLocation = true;
      _statusMessage = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _statusMessage =
              'Location services are turned off. Type a place name instead.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        setState(() {
          _statusMessage =
              'Location permission was denied. Type a place name instead.';
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _statusMessage =
              'Location permission is blocked in settings. Type a place name instead.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );

      final point = LatLng(position.latitude, position.longitude);
      final previousAutoLabel = _resolvedLabel;
      final provisionalLabel = ExpenseLocationService.formatCoordinates(
        point.latitude,
        point.longitude,
      );
      final requestId = ++_selectionRequestId;

      setState(() {
        _selectedPoint = point;
        _resolvedLabel = provisionalLabel;
        _isResolvingLocation = true;
        _statusMessage = 'Current location detected.';
      });

      if (_shouldSyncSearchField(previousAutoLabel, provisionalLabel)) {
        _replaceSearchText(provisionalLabel);
      }

      await _moveCamera(point);

      final resolvedLabel = await _locationService.resolveLabel(
        latitude: point.latitude,
        longitude: point.longitude,
      );
      if (!mounted || requestId != _selectionRequestId) {
        return;
      }

      setState(() {
        _resolvedLabel = resolvedLabel;
        _isResolvingLocation = false;
        _statusMessage = 'Current location detected.';
      });

      if (_shouldSyncSearchField(previousAutoLabel, provisionalLabel)) {
        _replaceSearchText(resolvedLabel);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage =
            'Current location could not be detected. Type a place name instead.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingCurrentLocation = false;
        });
      }
    }
  }

  Future<void> _selectPoint(LatLng point) async {
    final previousAutoLabel = _resolvedLabel;
    final provisionalLabel = ExpenseLocationService.formatCoordinates(
      point.latitude,
      point.longitude,
    );
    final requestId = ++_selectionRequestId;

    setState(() {
      _selectedPoint = point;
      _resolvedLabel = provisionalLabel;
      _isResolvingLocation = true;
      _statusMessage = null;
    });

    if (_shouldSyncSearchField(previousAutoLabel, provisionalLabel)) {
      _replaceSearchText(provisionalLabel);
    }

    final resolvedLabel = await _locationService.resolveLabel(
      latitude: point.latitude,
      longitude: point.longitude,
    );
    if (!mounted || requestId != _selectionRequestId) {
      return;
    }

    setState(() {
      _resolvedLabel = resolvedLabel;
      _isResolvingLocation = false;
    });

    if (_shouldSyncSearchField(previousAutoLabel, provisionalLabel)) {
      _replaceSearchText(resolvedLabel);
    }
  }

  Future<void> _refreshSelectionLabel({bool syncSearchField = false}) async {
    final point = _selectedPoint;
    if (point == null) {
      return;
    }

    final previousAutoLabel = _resolvedLabel;
    final provisionalLabel = ExpenseLocationService.formatCoordinates(
      point.latitude,
      point.longitude,
    );
    final requestId = ++_selectionRequestId;

    setState(() {
      _resolvedLabel = provisionalLabel;
      _isResolvingLocation = true;
    });

    if (syncSearchField &&
        _shouldSyncSearchField(previousAutoLabel, provisionalLabel)) {
      _replaceSearchText(provisionalLabel);
    }

    final resolvedLabel = await _locationService.resolveLabel(
      latitude: point.latitude,
      longitude: point.longitude,
    );
    if (!mounted || requestId != _selectionRequestId) {
      return;
    }

    setState(() {
      _resolvedLabel = resolvedLabel;
      _isResolvingLocation = false;
    });

    if (syncSearchField &&
        _shouldSyncSearchField(previousAutoLabel, provisionalLabel)) {
      _replaceSearchText(resolvedLabel);
    }
  }

  bool _shouldSyncSearchField(
    String? previousAutoLabel,
    String provisionalLabel,
  ) {
    final currentText = _searchController.text.trim();
    if (currentText.isEmpty) {
      return true;
    }

    if (currentText == provisionalLabel) {
      return true;
    }

    if (previousAutoLabel != null && currentText == previousAutoLabel.trim()) {
      return true;
    }

    return ExpenseLocationService.looksLikeCoordinateLabel(currentText);
  }

  Future<void> _moveCamera(LatLng point) async {
    if (_mapController == null) {
      return;
    }

    await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(point, 16));
  }

  void _submitSelection() {
    final label = _selectionLabel.trim();
    final point = _selectedPoint;
    if (label.isEmpty && point == null) {
      _showLocationMessage(
        'Search a place, type a label, or tap the map before saving.',
      );
      return;
    }

    final resolvedLabel = label.isNotEmpty
        ? label
        : ExpenseLocationService.formatCoordinates(
            point!.latitude,
            point.longitude,
          );

    Navigator.of(
      context,
    ).pop(ExpenseLocationSelection(label: resolvedLabel, position: point));
  }

  void _replaceSearchText(String value) {
    _searchController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );

    if (mounted) {
      setState(() {});
    }
  }

  void _showLocationMessage(String message) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

class _LocationPickerFooter extends StatelessWidget {
  const _LocationPickerFooter({required this.label, required this.onSave});

  final String label;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.trim().isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppPalette.ink,
              ),
            ),
          ),
        if (label.trim().isNotEmpty) const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.green,
              foregroundColor: AppPalette.ink,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: Text(
              'Save',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

class LabelSelectionScreen extends StatefulWidget {
  const LabelSelectionScreen({super.key, required this.initialSelection});

  final List<String> initialSelection;

  @override
  State<LabelSelectionScreen> createState() => _LabelSelectionScreenState();
}

class _LabelSelectionScreenState extends State<LabelSelectionScreen> {
  List<String> _selectedLabels = <String>[];

  @override
  void initState() {
    super.initState();
    _selectedLabels = <String>[...widget.initialSelection];
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _toggleSublabel(String label) {
    setState(() {
      if (_selectedLabels.contains(label)) {
        _selectedLabels.remove(label);
      } else {
        _selectedLabels = <String>[..._selectedLabels, label];
      }
    });
  }

  List<String> _orderedSelection() {
    final ordered = <String>[];

    for (final group in _expenseLabelGroups) {
      for (final label in group.sublabels) {
        if (_selectedLabels.contains(label)) {
          ordered.add(label);
        }
      }
    }

    return ordered;
  }

  void _save() {
    Navigator.of(context).pop(_orderedSelection());
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = 132.0 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            top: false,
            child: Column(
              children: [
                _ExpenseHeader(
                  isSubmitting: false,
                  title: 'Labels',
                  onClose: () => Navigator.of(context).pop(),
                  onConfirm: _save,
                  showConfirm: false,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final group in _expenseLabelGroups) ...[
                          Text(
                            group.label,
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppPalette.ink,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 12,
                            children: [
                              for (final label in group.sublabels)
                                _SublabelChip(
                                  label: label,
                                  selected: _selectedLabels.contains(label),
                                  onTap: () => _toggleSublabel(label),
                                ),
                            ],
                          ),
                          const SizedBox(height: 28),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Center(
                child: SizedBox(
                  width: 172,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.ink,
                      foregroundColor: Colors.white,
                      textStyle: GoogleFonts.nunito(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Done'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrencyThousandsFormatter extends TextInputFormatter {
  const _CurrencyThousandsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.isEmpty) {
      return const TextEditingValue();
    }

    final formatted = AppCurrencyFormatService.currency.format(
      int.parse(digitsOnly),
    );

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _ExpenseHeader extends StatelessWidget {
  const _ExpenseHeader({
    required this.title,
    required this.isSubmitting,
    required this.onClose,
    required this.onConfirm,
    this.showConfirm = true,
  });

  final String title;
  final bool isSubmitting;
  final VoidCallback onClose;
  final VoidCallback onConfirm;
  final bool showConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppPalette.green,
      padding: AppHeaderMetrics.padding(),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: AppPalette.ink),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppPalette.ink,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: showConfirm
                ? IconButton(
                    onPressed: isSubmitting ? null : onConfirm,
                    icon: const Icon(Icons.check, color: AppPalette.ink),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _ExpenseField extends StatelessWidget {
  const _ExpenseField({
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppPalette.field,
        border: Border(bottom: BorderSide(color: AppPalette.ink, width: 1.5)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          hintText: hintText,
          fillColor: Colors.transparent,
          filled: true,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide.none,
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide.none,
          ),
        ),
        style: GoogleFonts.nunito(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppPalette.ink,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppPalette.ink),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SublabelChip extends StatelessWidget {
  const _SublabelChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const Duration _animationDuration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pill,
        child: AnimatedContainer(
          duration: _animationDuration,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppPalette.green : Colors.white,
            borderRadius: AppRadius.pill,
            border: Border.all(
              color: selected ? AppPalette.green : const Color(0xFFD8D8D8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSize(
                duration: _animationDuration,
                curve: Curves.easeOut,
                child: selected
                    ? const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.check,
                          size: 15,
                          color: AppPalette.ink,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppPalette.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedExpenseLabelChip extends StatelessWidget {
  const _SelectedExpenseLabelChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pill,
        child: Container(
          height: _MiniActionButton.buttonHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppPalette.green,
            borderRadius: AppRadius.pill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check, size: 17, color: AppPalette.ink),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppPalette.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  static const double buttonHeight = 46;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadius.pill,
        child: Container(
          height: buttonHeight,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: AppPalette.green,
            borderRadius: AppRadius.pill,
          ),
          child: Center(
            widthFactor: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: AppPalette.ink),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
