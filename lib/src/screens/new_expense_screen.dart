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
import '../services/local_storage_service.dart';
import '../services/platform_configuration_service.dart';
import '../services/receipt_scan_service.dart';
import '../theme/spendant_theme.dart';

class _ExpenseLabelOption {
  const _ExpenseLabelOption({required this.label, required this.color});

  final String label;
  final Color color;
}

class _ExpenseLabelGroup {
  const _ExpenseLabelGroup({required this.label, required this.sublabels});

  final String label;
  final List<String> sublabels;
}

const List<_ExpenseLabelGroup> _expenseLabelGroups = <_ExpenseLabelGroup>[
  _ExpenseLabelGroup(
    label: 'Academic Essentials',
    sublabels: <String>[
      'University Fees',
      'Learning Materials',
      'Commute',
    ],
  ),
  _ExpenseLabelGroup(
    label: 'Lifestyle & Social',
    sublabels: <String>[
      'Social/Group Hangouts',
      'Food Delivery',
      'Entertainment',
      'Subscriptions',
    ],
  ),
  _ExpenseLabelGroup(
    label: 'Living Expenses',
    sublabels: <String>['Rent & Utilities', 'Groceries', 'Personal Care'],
  ),
  _ExpenseLabelGroup(
    label: 'Strategic & Utility Tags',
    sublabels: <String>[
      'Social Ledger (Owed)',
      'Goal Savings',
      'Impulse/Emotional',
      'Emergency',
    ],
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
    this.headerTitle = 'New Expense',
  });

  final ExpenseDraft? initialDraft;
  final String headerTitle;

  @override
  State<NewExpenseScreen> createState() => _NewExpenseScreenState();
}

class _NewExpenseScreenState extends State<NewExpenseScreen> {
  final TextEditingController _expenseNameController = TextEditingController();
  final TextEditingController _expenseValueController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final ReceiptScanService _receiptScanService = ReceiptScanService();

  static const List<_ExpenseLabelOption> _predefinedLabels =
      <_ExpenseLabelOption>[
        _ExpenseLabelOption(label: 'Food', color: AppPalette.food),
        _ExpenseLabelOption(label: 'Transport', color: AppPalette.transport),
        _ExpenseLabelOption(label: 'Services', color: AppPalette.services),
        _ExpenseLabelOption(label: 'Other', color: AppPalette.other),
      ];

  String? _selectedCategory;
  List<String> _selectedDetailLabels = <String>[];
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  ExpenseLocationSelection? _selectedLocation;
  bool _isScanningReceipt = false;

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
    final draft = widget.initialDraft;
    if (draft == null) {
      return;
    }

    _expenseNameController.text = draft.name;
    _expenseValueController.text = draft.amount;
    _selectedCategory = draft.primaryCategory;
    _selectedDetailLabels = <String>[...draft.detailLabels];
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
    final materialTextTheme =
        Typography.material2021(platform: defaultTargetPlatform).black;
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

  void _selectCategory(String label) {
    setState(() {
      _selectedCategory = _selectedCategory == label ? null : label;
    });
  }

  Future<void> _pickLabels() async {
    final selected = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => LabelSelectionScreen(
          initialSelection: _selectedDetailLabels,
        ),
      ),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _selectedDetailLabels = selected;
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
              ? LatLng(
                  result.location!.latitude!,
                  result.location!.longitude!,
                )
              : null,
        );
      }
    });
  }

  void _showScanMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _handleConfirm() async {
    FocusScope.of(context).unfocus();

    if (_selectedCategory == null) {
      _showScanMessage('Please choose a main category');
      return;
    }

    if (_selectedDetailLabels.isEmpty) {
      await _showMissingLabelWarning();
      return;
    }

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

    // Create expense model
    final expense = ExpenseModel()
      ..userId = 1 // TODO: Get actual user ID from auth
      ..name = _expenseNameController.text.trim()
      ..amount = parsedAmount
      ..date = _selectedDate
      ..time =
          '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}'
      ..latitude = _selectedLocation?.position?.latitude
      ..longitude = _selectedLocation?.position?.longitude
      ..locationName = _selectedLocation?.label
      ..source = 'MANUAL'
      ..receiptImagePath = null
      ..isPendingCategory = false
      ..isRecurring = false
      ..isSynced = false
      ..createdAt = DateTime.now()
      ..primaryCategory = _selectedCategory
      ..detailLabels = List<String>.from(_selectedDetailLabels);

    // Save to local storage
    await LocalStorageService().saveExpense(expense);

    if (!mounted) {
      return;
    }

    _showScanMessage('Expense saved locally');
    Navigator.of(context).pop(true);
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
                                    alignment: WrapAlignment.center,
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      for (final option in _predefinedLabels)
                                        _PrimaryCategoryChip(
                                          label: option.label,
                                          color: option.color,
                                          selected:
                                              _selectedCategory == option.label,
                                          onTap: () =>
                                              _selectCategory(option.label),
                                        ),
                                    ],
                                  ),
                                  if (_selectedDetailLabels.isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final label
                                            in _selectedDetailLabels)
                                          Chip(
                                            label: Text(label),
                                            backgroundColor:
                                                const Color(0xFFD1D1D1),
                                            deleteIconColor: AppPalette.ink,
                                            onDeleted: () {
                                              setState(() {
                                                _selectedDetailLabels.remove(
                                                  label,
                                                );
                                              });
                                            },
                                            labelStyle: GoogleFonts.nunito(
                                              fontWeight: FontWeight.w800,
                                              color: AppPalette.ink,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  Center(
                                    child: _MiniActionButton(
                                      icon: Icons.add,
                                      label: 'Label',
                                      onPressed: _pickLabels,
                                    ),
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
                                                child:
                                                    CircularProgressIndicator(
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

/* class _ReceiptReviewRow extends StatelessWidget {
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
    final materialTextTheme =
        Typography.material2021(platform: defaultTargetPlatform).black;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _ExpenseHeader(
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
          initialCameraPosition: CameraPosition(target: _selectedPoint, zoom: 16),
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
  final TextEditingController _searchController = TextEditingController();
  late List<String> _selectedLabels;
  String _query = '';
  String? _expandedGroupLabel;

  @override
  void initState() {
    super.initState();
    _selectedLabels = <String>[...widget.initialSelection];
    _expandedGroupLabel = _groupLabelForSelection(widget.initialSelection);
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
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

    final matchingSublabels =
        group.sublabels.where((label) => _matchesQuery(label)).toList();

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
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = 124.0 + keyboardInset;
    final visibleGroups = _visibleGroups();

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _ExpenseHeader(
                  title: 'Labels',
                  onClose: () => Navigator.of(context).pop(),
                  onConfirm: _save,
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final minHeight = math.max(
                        0.0,
                        constraints.maxHeight - bottomPadding,
                      );

                      return SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          24,
                          14,
                          24,
                          bottomPadding,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: minHeight),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: AppPalette.field,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: TextField(
                                  controller: _searchController,
                                  decoration: InputDecoration(
                                    hintText: 'Search Label',
                                    prefixIconConstraints:
                                        const BoxConstraints(minWidth: 16),
                                    suffixIcon: const Icon(
                                      Icons.search,
                                      color: AppPalette.fieldHint,
                                    ),
                                    fillColor: Colors.transparent,
                                    filled: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 16,
                                        ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(999),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(999),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(999),
                                      borderSide: const BorderSide(
                                        color: AppPalette.green,
                                      ),
                                    ),
                                  ),
                                  style: GoogleFonts.nunito(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppPalette.ink,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeInOut,
                                alignment: Alignment.topLeft,
                                child: Wrap(
                                  spacing: 7,
                                  runSpacing: 8,
                                  children: [
                                    for (final group in visibleGroups) ...[
                                      _LabelGroupChip(
                                        label: group.label,
                                        active:
                                            _expandedGroupLabel == group.label,
                                        onTap: () =>
                                            _toggleGroup(group.label),
                                      ),
                                      for (final label
                                          in _visibleSublabels(group))
                                        _SublabelChip(
                                          label: label,
                                          selected:
                                              _selectedLabels.contains(label),
                                          onTap: () =>
                                              _toggleSublabel(label),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
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
            bottom: 22 + keyboardInset,
            child: SafeArea(
              top: false,
              child: Center(
                child: SizedBox(
                  width: 88,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: _selectedLabels.isEmpty ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.ink,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFA6A6A6),
                      disabledForegroundColor: Colors.white,
                      textStyle: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const Text('Save'),
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

    final formatted = NumberFormat('#,###', 'en_US').format(
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
    required this.onClose,
    required this.onConfirm,
  });

  final String title;
  final VoidCallback onClose;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppPalette.green,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
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
          IconButton(
            onPressed: onConfirm,
            icon: const Icon(Icons.check, color: AppPalette.ink),
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
        border: Border(
          bottom: BorderSide(color: AppPalette.ink, width: 1.5),
        ),
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

class _PrimaryCategoryChip extends StatelessWidget {
  const _PrimaryCategoryChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  static const double chipHeight = 46;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: chipHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? color : AppPalette.green,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: AppPalette.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabelGroupChip extends StatelessWidget {
  const _LabelGroupChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = active ? AppPalette.green : AppPalette.ink;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Colors.white : const Color(0xFFE4E4E4),
          borderRadius: BorderRadius.circular(20),
          border: active
              ? Border.all(color: AppPalette.green, width: 1.5)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 13, color: foregroundColor),
            const SizedBox(width: 3),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: foregroundColor,
              ),
            ),
          ],
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
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppPalette.green : const Color(0xFFD1D1D1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppPalette.ink,
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

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: _PrimaryCategoryChip.chipHeight,
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

