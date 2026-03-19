import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/income_model.dart';
import '../services/cloud_sync_service.dart';
import '../services/daily_budget_service.dart';
import '../services/local_storage_service.dart';
import '../theme/spendant_theme.dart';
import '../widgets/spendant_bottom_nav.dart';

// ─────────────────────────────────────────────────────────
// BUDGET SCREEN (lista de ingresos)
// ─────────────────────────────────────────────────────────

class BudgetScreen extends StatelessWidget {
  const BudgetScreen({super.key});

  static const int _defaultUserId = 1;
  static final NumberFormat _currencyFormat = NumberFormat('#,###', 'en_US');

  static const List<Color> _cardColors = [
    Color(0xFFF9D5C5),
    Color(0xFFFFF3C4),
    Color(0xFFD5EAF9),
    Color(0xFFD5F9E0),
  ];

  String _recurrenceLabel(IncomeModel income) {
    if (income.type == 'JUST_ONCE') return 'Just once';
    final interval = income.recurrenceInterval ?? 1;
    final rawUnit = (income.recurrenceUnit ?? 'MONTHS');
    final unit = rawUnit[0] + rawUnit.substring(1).toLowerCase();
    if (interval == 1) return 'Every $unit';
    return 'Every $interval ${unit}s';
  }

  @override
  Widget build(BuildContext context) {
    final budgetDependencies = Listenable.merge(<Listenable>[
      LocalStorageService.incomesListenable,
      LocalStorageService.goalsListenable,
      LocalStorageService.expensesListenable,
    ]);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _BudgetHeader(onClose: () => Navigator.of(context).pop()),
          Expanded(
            child: AnimatedBuilder(
              animation: budgetDependencies,
              builder: (context, _) {
                final box = LocalStorageService.incomeBox;
                final incomes =
                    box.values.where((i) => i.userId == _defaultUserId).toList()
                      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                final summary = DailyBudgetService.buildSummaryForUser(
                  _defaultUserId,
                );

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  children: [
                    _BudgetSummaryCard(
                      summary: summary,
                      currencyFormat: _currencyFormat,
                    ),
                    const SizedBox(height: 14),
                    _IncomeSyncCard(
                      incomes: incomes,
                      currencyFormat: _currencyFormat,
                    ),
                    const SizedBox(height: 14),
                    if (summary.isSpendableBudgetExhausted) ...[
                      _BudgetNoticeCard(
                        message: summary.isInternalBudgetExhausted
                            ? 'Today\'s full daily budget is already gone, so no more money can move toward your goals today.'
                            : 'Your visible daily budget is already exhausted. Spending more today will affect the money reserved for your goals.',
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (incomes.isEmpty)
                      const _EmptyIncomesCard()
                    else
                      for (var i = 0; i < incomes.length; i++) ...[
                        _IncomeCard(
                          income: incomes[i],
                          color: _cardColors[i % _cardColors.length],
                          recurrenceLabel: _recurrenceLabel(incomes[i]),
                          currencyFormat: _currencyFormat,
                        ),
                        const SizedBox(height: 12),
                      ],
                    const SizedBox(height: 40),
                    Center(
                      child: ElevatedButton(
                        onPressed: () async {
                          final didSave = await Navigator.of(context)
                              .push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => const NewIncomeScreen(),
                                ),
                              );
                          if (didSave == true) {
                            unawaited(CloudSyncService().syncAllPendingData());
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppPalette.ink,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(180, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: Text(
                          'New Income',
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
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
      padding: const EdgeInsets.fromLTRB(8, 52, 8, 14),
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
  });

  final IncomeModel income;
  final Color color;
  final String recurrenceLabel;
  final NumberFormat currencyFormat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        income.name,
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppPalette.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _IncomeSyncBadge(isSynced: income.isSynced),
                  ],
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
                Text(
                  income.isSynced
                      ? 'Uploaded to Firebase'
                      : 'Saved locally. Pending cloud sync',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: income.isSynced
                        ? Colors.green.shade700
                        : Colors.orange.shade800,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'COP ${currencyFormat.format(income.amount.round())}',
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppPalette.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomeSyncBadge extends StatelessWidget {
  const _IncomeSyncBadge({required this.isSynced});

  final bool isSynced;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isSynced ? const Color(0xFFD7F6DE) : const Color(0xFFFFE1C2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isSynced ? 'Nube' : 'Local',
        style: GoogleFonts.nunito(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: AppPalette.ink,
        ),
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

class _IncomeSyncCard extends StatelessWidget {
  const _IncomeSyncCard({required this.incomes, required this.currencyFormat});

  final List<IncomeModel> incomes;
  final NumberFormat currencyFormat;

  Future<void> _syncNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final summary = await CloudSyncService().syncAllPendingData();
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Incomes synced. Uploaded ${summary.uploadedIncomes} income(s). Failures: ${summary.failures}.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Income sync failed: $error')),
      );
    }
  }

  Future<void> _verifyNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final verification = await CloudSyncService().verifyCloudState();
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Firestore incomes: ${verification.remoteIncomes}. Pending local incomes: ${verification.pendingIncomes}. Missing remote incomes: ${verification.missingIncomes}.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Cloud verification failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingIncomes = incomes.where((income) => !income.isSynced).length;
    final syncedIncomes = incomes.length - pendingIncomes;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.field,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Income sync status',
            style: GoogleFonts.nunito(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppPalette.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Create an income offline and it will stay Local. When internet comes back, tap Sync now or wait for the background retry until it changes to Nube.',
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppPalette.fieldHint,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _BudgetSummaryStat(
                  label: 'Local pending',
                  value: '$pendingIncomes',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BudgetSummaryStat(
                  label: 'Uploaded',
                  value: '$syncedIncomes',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton(
                onPressed: () => _syncNow(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.ink,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Sync now'),
              ),
              OutlinedButton(
                onPressed: () => _verifyNow(context),
                child: const Text('Verify cloud'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// NEW INCOME SCREEN (formulario)
// ─────────────────────────────────────────────────────────

class _BudgetSummaryCard extends StatelessWidget {
  const _BudgetSummaryCard({
    required this.summary,
    required this.currencyFormat,
  });

  final DailyBudgetSummary summary;
  final NumberFormat currencyFormat;

  String _format(double amount) {
    return 'COP ${currencyFormat.format(amount.round())}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.field,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily budget overview',
            style: GoogleFonts.nunito(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppPalette.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Internal budget comes from your incomes. The user budget is what remains after reserving the daily savings needed for all goals.',
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppPalette.fieldHint,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _BudgetSummaryStat(
                  label: 'Internal',
                  value: _format(summary.internalDailyBudget),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BudgetSummaryStat(
                  label: 'Goals reserve',
                  value: _format(summary.totalGoalDailyCommitment),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _BudgetSummaryStat(
                  label: 'User budget',
                  value: _format(summary.spendableDailyBudget),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BudgetSummaryStat(
                  label: 'Spent today',
                  value: _format(summary.todayExpenses),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BudgetSummaryStat extends StatelessWidget {
  const _BudgetSummaryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
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
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppPalette.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetNoticeCard extends StatelessWidget {
  const _BudgetNoticeCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0D9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, color: AppPalette.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppPalette.ink,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NewIncomeScreen extends StatefulWidget {
  const NewIncomeScreen({super.key});

  @override
  State<NewIncomeScreen> createState() => _NewIncomeScreenState();
}

class _NewIncomeScreenState extends State<NewIncomeScreen> {
  static const int _defaultUserId = 1;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _intervalController = TextEditingController(
    text: '1',
  );

  String _type = 'JUST_ONCE';
  String _recurrenceUnit = 'WEEKS';
  DateTime _selectedDate = DateTime.now();
  bool _isSavingIncome = false;

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

    final income = IncomeModel()
      ..userId = _defaultUserId
      ..name = _nameController.text.trim()
      ..amount = parsedAmount
      ..type = _type
      ..recurrenceInterval = _type == 'FREQUENTLY' ? interval : null
      ..recurrenceUnit = _type == 'FREQUENTLY' ? _recurrenceUnit : null
      ..startDate = _selectedDate
      ..createdAt = DateTime.now()
      ..isSynced = false;

    try {
      await LocalStorageService().saveIncome(income);
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

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    messenger.showSnackBar(
      const SnackBar(content: Text('Income saved locally')),
    );
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _NewIncomeHeader(
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
    required this.isSubmitting,
    required this.onClose,
    required this.onConfirm,
  });

  final bool isSubmitting;
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
            onPressed: isSubmitting ? null : onClose,
            icon: const Icon(Icons.close, color: AppPalette.ink),
          ),
          Expanded(
            child: Text(
              'New Income',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppPalette.ink,
              ),
            ),
          ),
          IconButton(
            onPressed: isSubmitting ? null : onConfirm,
            icon: isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppPalette.ink,
                    ),
                  )
                : const Icon(Icons.check, color: AppPalette.ink),
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
              DateFormat('d/MM/yyyy').format(date),
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
