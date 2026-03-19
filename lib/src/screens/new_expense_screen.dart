import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/expense_draft.dart';
import '../models/expense_model.dart';
import '../services/cloud_sync_service.dart';
import '../services/local_storage_service.dart';
import '../services/platform_configuration_service.dart';
import '../services/receipt_scan_service.dart';
import '../theme/spendant_theme.dart';

class _ExpenseLabelGroup {
  const _ExpenseLabelGroup({required this.label, required this.sublabels});

  final String label;
  final List<String> sublabels;
}

const List<_ExpenseLabelGroup> _expenseLabelGroups = <_ExpenseLabelGroup>[
  _ExpenseLabelGroup(
    label: 'Academic Essentials',
    sublabels: <String>[
      'Commute',
      'Learning Materials',
      'University Fees',
    ],
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
    sublabels: <String>[
      'Emergency',
      'Impulse',
      'Owed',
    ],
  ),
];

const Map<String, String> _detailLabelPrimaryCategories = <String, String>{
  'Food': 'Food',
  'Food Delivery': 'Food',
  'Groceries': 'Food',
  'Commute': 'Transport',
  'Transport': 'Transport',
  'Learning Materials': 'Services',
  'University Fees': 'Services',
  'Personal Care': 'Services',
  'Rent': 'Services',
  'Services': 'Services',
  'Utilities': 'Services',
  'Entertainment': 'Other',
  'Gifts': 'Other',
  'Group Hangouts': 'Other',
  'Subscriptions': 'Other',
  'Emergency': 'Other',
  'Impulse': 'Other',
  'Owed': 'Other',
};

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
  final TextEditingController _expenseNameController = TextEditingController();
  final TextEditingController _expenseValueController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final ReceiptScanService _receiptScanService = ReceiptScanService();

  String? _selectedCategory;
  List<String> _selectedDetailLabels = <String>[];
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  ExpenseLocationSelection? _selectedLocation;
  bool _isScanningReceipt = false;
  bool _isSavingExpense = false;

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
      _expenseNameController.text = editingExpense.name;
      _expenseValueController.text = NumberFormat(
        '#,###',
        'en_US',
      ).format(editingExpense.amount.round());
      _selectedCategory = editingExpense.primaryCategory;
      _selectedDetailLabels = <String>[...editingExpense.detailLabels];
      _selectedCategory =
          _derivePrimaryCategory(_selectedDetailLabels) ??
          editingExpense.primaryCategory;
      _selectedDate = editingExpense.date;

      final timeParts = editingExpense.time.split(':');
      _selectedTime = TimeOfDay(
        hour: timeParts.isNotEmpty ? int.tryParse(timeParts[0]) ?? 0 : 0,
        minute: timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0,
      );

      if ((editingExpense.locationName ?? '').trim().isNotEmpty) {
        _selectedLocation = ExpenseLocationSelection(
          label: editingExpense.locationName!.trim(),
          position:
              editingExpense.latitude != null && editingExpense.longitude != null
              ? LatLng(editingExpense.latitude!, editingExpense.longitude!)
              : null,
        );
      }
      return;
    }

    final draft = widget.initialDraft;
    if (draft == null) {
      return;
    }

    _expenseNameController.text = draft.name;
    _expenseValueController.text = draft.amount;
    _selectedCategory = draft.primaryCategory;
    _selectedDetailLabels = <String>[...draft.detailLabels];
    _selectedCategory =
        _derivePrimaryCategory(_selectedDetailLabels) ?? draft.primaryCategory;
    _selectedDate = draft.date;
    _selectedTime = draft.time;

    if (draft.locationLabel != null && draft.locationLabel!.trim().isNotEmpty) {
      _selectedLocation = ExpenseLocationSelection(
        label: draft.locationLabel!.trim(),
        position: draft.latitude != null && draft.longitude != null
            ? LatLng(draft.latitude!, draft.longitude!)
            : null,
      );
    }
  }

  String? _derivePrimaryCategory(List<String> labels) {
    for (final label in labels) {
      final category = _detailLabelPrimaryCategories[label];
      if (category != null) {
        return category;
      }
    }

    if (labels.isNotEmpty) {
      return 'Other';
    }

    return null;
  }

  void _applySelectedLabels(List<String> labels) {
    _selectedDetailLabels = labels;
    _selectedCategory = _derivePrimaryCategory(labels);
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
    final materialTextTheme = Typography.material2021(
      platform: defaultTargetPlatform,
    ).black;
    const timeDisplayHeight = 64 / 57;
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
              helpTextStyle: materialTextTheme.labelMedium?.copyWith(
                color: AppPalette.fieldHint,
              ),
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
              hourMinuteTextStyle: materialTextTheme.displayLarge?.copyWith(
                fontSize: 57,
                height: timeDisplayHeight,
                color: AppPalette.ink,
              ),
              timeSelectorSeparatorColor: const WidgetStatePropertyAll<Color?>(
                AppPalette.ink,
              ),
              timeSelectorSeparatorTextStyle:
                  WidgetStatePropertyAll<TextStyle?>(
                    materialTextTheme.displayLarge?.copyWith(
                      fontSize: 57,
                      height: timeDisplayHeight,
                      color: AppPalette.ink,
                    ),
                  ),
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
              dayPeriodTextStyle: materialTextTheme.labelMedium?.copyWith(
                color: AppPalette.fieldHint,
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
              dialTextStyle: materialTextTheme.bodyLarge?.copyWith(
                color: AppPalette.ink,
              ),
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
                  vertical: 16,
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

  Future<void> _pickLocation() async {
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

  void _removeSelectedLabel(String label) {
    setState(() {
      final updated = List<String>.from(_selectedDetailLabels)
        ..remove(label);
      _applySelectedLabels(updated);
    });
  }

  Future<void> _scanReceipt() async {
    if (kIsWeb) {
      final result = await Navigator.of(context).push<ReceiptScanResult>(
        MaterialPageRoute(builder: (_) => const _MockReceiptScannerScreen()),
      );
      if (result != null && mounted) {
        _applyReceiptScanResult(result);
        _showScanMessage(
          'Receipt scanned. Review the detected fields before saving.',
        );
      }
      return;
    }

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

  void _showScanMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _handleConfirm() async {
    if (_isSavingExpense) {
      return;
    }

    FocusScope.of(context).unfocus();

    if (_selectedDetailLabels.isEmpty) {
      await _showMissingLabelWarning();
      return;
    }

    _selectedCategory ??= _derivePrimaryCategory(_selectedDetailLabels) ?? 'Other';

    // Validate required fields
    if (_expenseNameController.text.trim().isEmpty) {
      _showScanMessage('Please enter an expense name');
      return;
    }

    final amountText = _expenseValueController.text.replaceAll(',', '').trim();
    final parsedAmount = double.tryParse(amountText);
    if (amountText.isEmpty || parsedAmount == null || parsedAmount <= 0) {
      _showScanMessage('Please enter a valid amount');
      return;
    }

    setState(() {
      _isSavingExpense = true;
    });

    // Create expense model
    final expense = ExpenseModel()
      ..userId =
          1 // TODO: Get actual user ID from auth
      ..name = _expenseNameController.text.trim()
      ..amount = parsedAmount
      ..date = _selectedDate
      ..time =
          '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}'
      ..latitude = _selectedLocation?.position?.latitude
      ..longitude = _selectedLocation?.position?.longitude
      ..locationName = _selectedLocation?.label
      ..source = expense.source.isEmpty ? 'MANUAL' : expense.source
      ..receiptImagePath = expense.receiptImagePath
      ..isPendingCategory = false
      ..isRecurring = expense.isRecurring
      ..isSynced = false
      ..createdAt = widget.editingExpense?.createdAt ?? DateTime.now()
      ..primaryCategory = _selectedCategory
      ..detailLabels = List<String>.from(_selectedDetailLabels);

    try {
      await LocalStorageService().saveExpense(expense);
    } catch (_) {
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

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    messenger.showSnackBar(
      const SnackBar(content: Text('Expense saved locally')),
    );
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
                  "I don't recognize this expense yet. Give it a label so I can learn for next time.",
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
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final formBottomPadding = 116.0 + keyboardInset;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _ExpenseHeader(
                  title: widget.headerTitle,
                  isSubmitting: _isSavingExpense,
                  onClose: () => Navigator.of(context).maybePop(),
                  onConfirm: () {
                    _handleConfirm();
                  },
                ),
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
                                      child: ElevatedButton.icon(
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
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                            horizontal: 14,
                                          ),
                                          textStyle: GoogleFonts.nunito(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_lastReceiptScanResult != null &&
                                      _lastReceiptScanResult!
                                          .hasDetectedData) ...[
                                    const SizedBox(height: 20),
                                    _ReceiptReviewCard(
                                      result: _lastReceiptScanResult!,
                                    ),
                                  ],
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
                        label: DateFormat('d/M/y').format(_selectedDate),
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

class _ReceiptReviewCard extends StatelessWidget {
  const _ReceiptReviewCard({required this.result});

  final ReceiptScanResult result;

  @override
  Widget build(BuildContext context) {
    final rows = <({IconData icon, String label, String value})>[
      if (result.name != null && result.name!.trim().isNotEmpty)
        (
          icon: Icons.storefront_outlined,
          label: 'Expense name',
          value: result.name!.trim(),
        ),
      if (result.formattedAmount != null &&
          result.formattedAmount!.trim().isNotEmpty)
        (
          icon: Icons.payments_outlined,
          label: 'Amount',
          value: '\$ ${result.formattedAmount!.trim()}',
        ),
      if (result.date != null)
        (
          icon: Icons.calendar_today_outlined,
          label: 'Date',
          value: DateFormat('d/M/y').format(result.date!),
        ),
      if (result.time != null)
        (
          icon: Icons.access_time,
          label: 'Time',
          value: TimeOfDay.fromDateTime(
            result.time!,
          ).format(context).toLowerCase(),
        ),
      if (result.location != null && result.location!.label.trim().isNotEmpty)
        (
          icon: Icons.location_on_outlined,
          label: 'Location',
          value: result.location!.label.trim(),
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: AppPalette.field,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.green, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Receipt added to manual logging',
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppPalette.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Review the detected values below and confirm the expense when everything looks right.',
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppPalette.fieldHint,
            ),
          ),
          const SizedBox(height: 14),
          for (final row in rows) ...[
            _ReceiptReviewRow(
              icon: row.icon,
              label: row.label,
              value: row.value,
            ),
            if (row != rows.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ReceiptReviewRow extends StatelessWidget {
  const _ReceiptReviewRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: AppPalette.ink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.fieldHint,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
} */

// ─────────────────────────────────────────────────────────
// MOCK RECEIPT SCANNER (web / demo)
// ─────────────────────────────────────────────────────────

class _MockReceiptScannerScreen extends StatefulWidget {
  const _MockReceiptScannerScreen();

  @override
  State<_MockReceiptScannerScreen> createState() =>
      _MockReceiptScannerScreenState();
}

class _MockReceiptScannerScreenState
    extends State<_MockReceiptScannerScreen> {
  bool _scanning = false;

  static final ReceiptScanResult _mockResult = ReceiptScanResult(
    name: 'Ajiaco y Frijoles Centro Histórico',
    formattedAmount: '25,020',
    date: DateTime(2026, 3, 19),
    time: DateTime(2026, 3, 19, 13, 45),
    location: const ReceiptScanLocation(
      label: 'Calle 20 #6-76, Bogotá',
    ),
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
                  Positioned(
                    top: 60,
                    left: 40,
                    child: _CornerGuide(rotate: 0),
                  ),
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
                borderRadius: BorderRadius.circular(999),
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
  const DateSelectionScreen({super.key, required this.initialDate});

  final DateTime initialDate;

  @override
  State<DateSelectionScreen> createState() => _DateSelectionScreenState();
}

class _DateSelectionScreenState extends State<DateSelectionScreen> {
  late DateTime _selectedDate = widget.initialDate;

  @override
  Widget build(BuildContext context) {
    final materialTextTheme = Typography.material2021(
      platform: defaultTargetPlatform,
    ).black;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _ExpenseHeader(
              isSubmitting: false,
              title: 'Select Date',
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
                          firstDate: DateTime(2020),
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

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const LatLng _defaultCenter = LatLng(4.60971, -74.08175);

  late LatLng _selectedPoint = widget.initialValue?.position ?? _defaultCenter;
  late final Future<bool> _hasGoogleMapsApiKeyFuture =
      PlatformConfigurationService.hasGoogleMapsApiKey();

  @override
  Widget build(BuildContext context) {
    final label =
        '${_selectedPoint.latitude.toStringAsFixed(4)}, ${_selectedPoint.longitude.toStringAsFixed(4)}';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _ExpenseHeader(
              isSubmitting: false,
              title: 'Select Location',
              onClose: () => Navigator.of(context).pop(),
              onConfirm: () {
                Navigator.of(context).pop(
                  ExpenseLocationSelection(
                    position: _selectedPoint,
                    label: label,
                  ),
                );
              },
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: Column(
                  children: [
                    TextField(
                      readOnly: true,
                      decoration: InputDecoration(
                        hintText: 'Search label',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: const Icon(Icons.location_on_outlined),
                        fillColor: Colors.white,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: BorderSide.none,
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
                                child: Center(
                                  child: SizedBox(
                                    width: 120,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        Navigator.of(context).pop(
                                          ExpenseLocationSelection(
                                            position: _selectedPoint,
                                            label: label,
                                          ),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppPalette.green,
                                        foregroundColor: AppPalette.ink,
                                      ),
                                      child: Text(
                                        'Save',
                                        style: GoogleFonts.nunito(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
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
    if (kIsWeb) {
      return _buildMapFallback(
        'Google Maps on web needs a configured JavaScript API key. The crash is blocked for now, and you can still save the current point.',
      );
    }

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
            'Google Maps needs a configured native API key on this app. The map was not opened to avoid the Android crash, but you can still save the current point.',
          );
        }

        return GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _selectedPoint,
            zoom: 16,
          ),
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onTap: (point) {
            setState(() {
              _selectedPoint = point;
            });
          },
          markers: {
            Marker(
              markerId: const MarkerId('selected-location'),
              position: _selectedPoint,
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
}

class LabelSelectionScreen extends StatefulWidget {
  const LabelSelectionScreen({super.key, required this.initialSelection});

  final List<String> initialSelection;

  @override
  State<LabelSelectionScreen> createState() => _LabelSelectionScreenState();
}

class _LabelSelectionScreenState extends State<LabelSelectionScreen> {
  late List<String> _selectedLabels;

  @override
  void initState() {
    super.initState();
    _selectedLabels = <String>[...widget.initialSelection];
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _handleSearchChanged() {
    setState(() {
      _query = _searchController.text.trim().toLowerCase();
    });
  }

  String? _groupLabelForSelection(List<String> selection) {
    for (final label in selection) {
      for (final group in _expenseLabelGroups) {
        if (group.sublabels.contains(label)) {
          return group.label;
        }
      }
    }
    return null;
  }

  bool _matchesQuery(String value) {
    if (_query.isEmpty) {
      return true;
    }
    return value.toLowerCase().contains(_query);
  }

  List<_ExpenseLabelGroup> _visibleGroups() {
    if (_query.isEmpty) {
      return _expenseLabelGroups;
    }

    return _expenseLabelGroups.where((group) {
      return _matchesQuery(group.label) ||
          group.sublabels.any((label) => _matchesQuery(label));
    }).toList();
  }

  List<String> _visibleSublabels(_ExpenseLabelGroup group) {
    if (_query.isEmpty) {
      if (_expandedGroupLabel != group.label) {
        return const <String>[];
      }
      return group.sublabels;
    }

    final matchingSublabels = group.sublabels
        .where((label) => _matchesQuery(label))
        .toList();

    if (matchingSublabels.isNotEmpty) {
      return matchingSublabels;
    }

    if (_matchesQuery(group.label)) {
      return group.sublabels;
    }

    return const <String>[];
  }

  void _toggleGroup(String label) {
    setState(() {
      _expandedGroupLabel = _expandedGroupLabel == label ? null : label;
    });
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
    final bottomPadding = 132.0 + MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
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

    final formatted = NumberFormat(
      '#,###',
      'en_US',
    ).format(int.parse(digitsOnly));

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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Row(
        children: [
          IconButton(
            onPressed: isSubmitting ? null : onClose,
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
                    onPressed: onConfirm,
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

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppPalette.green : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppPalette.green : const Color(0xFFD8D8D8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: selected ? 1 : 0,
              child: const Icon(Icons.check, size: 15, color: AppPalette.ink),
            ),
            const SizedBox(width: 6),
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
    );
  }
}

class _SelectedExpenseLabelChip extends StatelessWidget {
  const _SelectedExpenseLabelChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: _MiniActionButton.buttonHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppPalette.green,
            borderRadius: BorderRadius.circular(999),
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
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: buttonHeight,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: AppPalette.green,
            borderRadius: BorderRadius.circular(999),
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
