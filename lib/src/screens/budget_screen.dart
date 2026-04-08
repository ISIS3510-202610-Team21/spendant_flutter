import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../models/income_model.dart';
import '../services/app_date_format_service.dart';
import '../services/app_notification_service.dart';
import '../services/auth_memory_store.dart';
import '../services/cloud_sync_service.dart';
import '../services/local_storage_service.dart';
import '../theme/spendant_theme.dart';
import '../widgets/auth_chrome.dart';
import '../widgets/spendant_bottom_nav.dart';
import '../widgets/spendant_delete_dialog.dart';
import '../../app.dart';

// ─────────────────────────────────────────────────────────
// BUDGET SCREEN (lista de ingresos)
// ─────────────────────────────────────────────────────────

class BudgetScreen extends StatelessWidget {
  const BudgetScreen({super.key});

  static final NumberFormat _currencyFormat = NumberFormat('#,###', 'en_US');
  static const double _bottomDockButtonOffset = 40;
  static const double _bottomDockButtonClearance = 112;

  static const List<Color> _cardColors = [
    Color(0xFFF9D5C5),
    Color(0xFFFFF3C4),
    Color(0xFFD5EAF9),
    Color(0xFFD5F9E0),
  ];

  int get _currentUserId => AuthMemoryStore.currentUserIdOrGuest;

  void _goToHome(BuildContext context) {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  String _recurrenceLabel(IncomeModel income) {
    if (income.type == 'JUST_ONCE') return 'Just once';
    final interval = income.recurrenceInterval ?? 1;
    final rawUnit = (income.recurrenceUnit ?? 'MONTHS');
    final unit = rawUnit[0] + rawUnit.substring(1).toLowerCase();
    if (interval == 1) return 'Every $unit';
    return 'Every $interval ${unit}s';
  }

  Future<bool> _showDeleteConfirmation(
    BuildContext context, {
    required String title,
    required String name,
  }) async {
    return showSpendAntDeleteDialog(context, title: title, name: name);
  }

  Future<void> _confirmDeleteIncome(
    BuildContext context,
    IncomeModel income,
  ) async {
    final shouldDelete = await _showDeleteConfirmation(
      context,
      title: 'Delete income?',
      name: income.name,
    );
    if (!shouldDelete || !context.mounted) {
      return;
    }

    final deletedFromCloud = await CloudSyncService().deleteIncomeRecord(
      income,
    );
    if (!context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text(
            deletedFromCloud
                ? 'Income deleted'
                : 'Income deleted locally. Cloud cleanup is still pending.',
          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _BudgetHeader(onClose: () => _goToHome(context)),
          Expanded(
            child: Stack(
              children: [
                ValueListenableBuilder<Box<IncomeModel>>(
                  valueListenable: LocalStorageService.incomesListenable,
                  builder: (context, box, _) {
                    final incomes =
                        box.values
                            .where((i) => i.userId == _currentUserId)
                            .toList()
                          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(
                        20,
                        24,
                        20,
                        _bottomDockButtonClearance,
                      ),
                      children: [
                        if (incomes.isEmpty)
                          const _EmptyIncomesCard()
                        else
                          for (var i = 0; i < incomes.length; i++) ...[
                            _IncomeCard(
                              income: incomes[i],
                              color: _cardColors[i % _cardColors.length],
                              recurrenceLabel: _recurrenceLabel(incomes[i]),
                              currencyFormat: _currencyFormat,
                              onDelete: () =>
                                  _confirmDeleteIncome(context, incomes[i]),
                              onEdit: () async {
                                await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => NewIncomeScreen(
                                      editingIncome: incomes[i],
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                      ],
                    );
                  },
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _bottomDockButtonOffset,
                  child: Center(
                    child: BlackPrimaryButton(
                      label: 'New Income',
                      width: null,
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      borderRadius: BorderRadius.circular(12),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: () async {
                        await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => const NewIncomeScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SpendAntBottomNav(currentItem: SpendAntNavItem.cards),
        ],
      ),
    );
  }
}

class _BudgetHeader extends StatelessWidget {
  const _BudgetHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppPalette.green,
      padding: AppHeaderMetrics.padding(horizontal: 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, color: AppPalette.ink),
            ),
          ),
          Text(
            'Budget and Income',
            style: GoogleFonts.nunito(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppPalette.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomeCard extends StatelessWidget {
  const _IncomeCard({
    required this.income,
    required this.color,
    required this.recurrenceLabel,
    required this.currencyFormat,
    required this.onDelete,
    required this.onEdit,
  });

  final IncomeModel income;
  final Color color;
  final String recurrenceLabel;
  final NumberFormat currencyFormat;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFD0D0D0), width: 2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppPalette.ink.withValues(alpha: 0.08),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: AppPalette.ink,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  income.name,
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  recurrenceLabel,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.ink.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Starts ${AppDateFormatService.longDate(income.startDate)}',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'COP ${currencyFormat.format(income.amount.round())}',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppPalette.ink,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppPalette.ink,
                    ),
                    tooltip: 'Delete income',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    splashRadius: 18,
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: AppPalette.ink,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyIncomesCard extends StatelessWidget {
  const _EmptyIncomesCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          'No incomes yet.\nTap "New Income" to add one.',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppPalette.fieldHint,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// NEW INCOME SCREEN (formulario)
// ─────────────────────────────────────────────────────────

class NewIncomeScreen extends StatefulWidget {
  const NewIncomeScreen({super.key, this.editingIncome});

  final IncomeModel? editingIncome;

  @override
  State<NewIncomeScreen> createState() => _NewIncomeScreenState();
}

class _NewIncomeScreenState extends State<NewIncomeScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _intervalController = TextEditingController(
    text: '1',
  );

  String _type = 'JUST_ONCE';
  String _recurrenceUnit = 'WEEKS';
  DateTime _selectedDate = DateTime.now();
  bool _isSavingIncome = false;

  bool get _isEditing => widget.editingIncome != null;
  int get _currentUserId => AuthMemoryStore.currentUserIdOrGuest;

  @override
  void initState() {
    super.initState();

    final editingIncome = widget.editingIncome;
    if (editingIncome == null) {
      return;
    }

    _nameController.text = editingIncome.name;
    _amountController.text = NumberFormat(
      '#,###',
      'en_US',
    ).format(editingIncome.amount.round());
    _type = editingIncome.type;
    _recurrenceUnit = editingIncome.recurrenceUnit ?? 'WEEKS';
    _intervalController.text = '${editingIncome.recurrenceInterval ?? 1}';
    _selectedDate = editingIncome.startDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppPalette.green,
              onPrimary: AppPalette.ink,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _handleConfirm() async {
    if (_isSavingIncome) {
      return;
    }

    FocusScope.of(context).unfocus();

    if (_nameController.text.trim().isEmpty) {
      _showMessage('Please enter an income name');
      return;
    }

    final amountText = _amountController.text.replaceAll(',', '').trim();
    final parsedAmount = double.tryParse(amountText);
    if (amountText.isEmpty || parsedAmount == null || parsedAmount <= 0) {
      _showMessage('Please enter a valid amount');
      return;
    }

    int? interval;
    if (_type == 'FREQUENTLY') {
      interval = int.tryParse(_intervalController.text.trim());
      if (interval == null || interval < 1) {
        _showMessage('Please enter a valid recurrence interval');
        return;
      }
    }

    setState(() {
      _isSavingIncome = true;
    });

    IncomeModel? createdIncome;
    try {
      final editingIncome = widget.editingIncome;
      if (editingIncome == null) {
        final income = IncomeModel()
          ..userId = _currentUserId
          ..name = _nameController.text.trim()
          ..amount = parsedAmount
          ..type = _type
          ..recurrenceInterval = _type == 'FREQUENTLY' ? interval : null
          ..recurrenceUnit = _type == 'FREQUENTLY' ? _recurrenceUnit : null
          ..startDate = _selectedDate
          ..createdAt = DateTime.now()
          ..isSynced = false;
        await LocalStorageService().saveIncome(income);
        createdIncome = income;
      } else {
        editingIncome
          ..userId = _currentUserId
          ..name = _nameController.text.trim()
          ..amount = parsedAmount
          ..type = _type
          ..recurrenceInterval = _type == 'FREQUENTLY' ? interval : null
          ..recurrenceUnit = _type == 'FREQUENTLY' ? _recurrenceUnit : null
          ..startDate = _selectedDate
          ..isSynced = false;
        await editingIncome.save();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingIncome = false;
      });
      _showMessage('The income could not be saved');
      return;
    }

    if (!mounted) {
      return;
    }

    if (createdIncome != null) {
      unawaited(AppNotificationService.notifyIncomeCreated(createdIncome));
    }
    final navigator = Navigator.of(context);
    navigator.pop(true);
    _syncPendingDataInBackground();
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

  void _showMessage(String message) {
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

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _NewIncomeHeader(
              title: _isEditing ? 'Edit Income' : 'New Income',
              isSubmitting: _isSavingIncome,
              onClose: () => Navigator.of(context).maybePop(),
              onConfirm: _handleConfirm,
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(24, 32, 24, 24 + keyboardInset),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _IncomeField(
                        controller: _nameController,
                        hintText: 'Income name',
                      ),
                      const SizedBox(height: 20),
                      _IncomeField(
                        controller: _amountController,
                        hintText: r'$ 0',
                        keyboardType: TextInputType.number,
                        inputFormatters: [const _CurrencyThousandsFormatter()],
                      ),
                      const SizedBox(height: 28),
                      Center(
                        child: Text(
                          'Type of Income',
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TypeChip(
                              label: 'Just Once',
                              selected: _type == 'JUST_ONCE',
                              onTap: () => setState(() => _type = 'JUST_ONCE'),
                            ),
                            const SizedBox(width: 10),
                            _TypeChip(
                              label: 'Frequently',
                              selected: _type == 'FREQUENTLY',
                              onTap: () => setState(() => _type = 'FREQUENTLY'),
                            ),
                          ],
                        ),
                      ),
                      if (_type == 'FREQUENTLY') ...[
                        const SizedBox(height: 16),
                        Center(
                          child: _RecurrenceRow(
                            intervalController: _intervalController,
                            selectedUnit: _recurrenceUnit,
                            onUnitChanged: (unit) =>
                                setState(() => _recurrenceUnit = unit),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Center(
                        child: _DateRow(date: _selectedDate, onTap: _pickDate),
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

class _NewIncomeHeader extends StatelessWidget {
  const _NewIncomeHeader({
    required this.title,
    required this.isSubmitting,
    required this.onClose,
    required this.onConfirm,
  });

  final String title;
  final bool isSubmitting;
  final VoidCallback onClose;
  final VoidCallback onConfirm;

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
          IconButton(
            onPressed: onConfirm,
            icon: const Icon(Icons.check, color: AppPalette.ink),
          ),
        ],
      ),
    );
  }
}

class _IncomeField extends StatelessWidget {
  const _IncomeField({
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
          focusedBorder: const OutlineInputBorder(
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

class _TypeChip extends StatelessWidget {
  const _TypeChip({
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
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppPalette.green : const Color(0xFFE4E4E4),
          borderRadius: BorderRadius.circular(999),
          border: selected
              ? Border.all(color: AppPalette.green, width: 1.5)
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppPalette.ink,
          ),
        ),
      ),
    );
  }
}

class _RecurrenceRow extends StatelessWidget {
  const _RecurrenceRow({
    required this.intervalController,
    required this.selectedUnit,
    required this.onUnitChanged,
  });

  final TextEditingController intervalController;
  final String selectedUnit;
  final ValueChanged<String> onUnitChanged;

  static const List<String> _units = ['DAYS', 'WEEKS', 'MONTHS'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Every',
          style: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppPalette.ink,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          child: Container(
            decoration: BoxDecoration(
              color: AppPalette.field,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: intervalController,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppPalette.ink,
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        DropdownButtonHideUnderline(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: AppPalette.field,
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButton<String>(
              value: selectedUnit,
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppPalette.ink,
              ),
              dropdownColor: AppPalette.field,
              borderRadius: BorderRadius.circular(12),
              items: _units
                  .map(
                    (u) => DropdownMenuItem(
                      value: u,
                      child: Text(
                        u[0] + u.substring(1).toLowerCase(),
                        style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w800,
                          color: AppPalette.ink,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onUnitChanged(value);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: AppPalette.ink,
            ),
            const SizedBox(width: 10),
            Text(
              AppDateFormatService.longDate(date),
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppPalette.ink,
              ),
            ),
          ],
        ),
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
    if (digitsOnly.isEmpty) return const TextEditingValue();

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
