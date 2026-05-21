import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:wear/wear.dart';

import '../models/expense_model.dart';
import '../services/app_currency_format_service.dart';
import '../services/app_time_format_service.dart';
import '../services/auth_memory_store.dart';
import '../services/local_storage_service.dart';
import '../services/wear_expense_sync_service.dart';
import '../theme/spendant_theme.dart';

// ─── Voice input ────────────────────────────────────────────────────────────

const _voiceChannel = MethodChannel('spendant_flutter/voice_input');

Future<String?> _startVoiceInput() async {
  try {
    return await _voiceChannel.invokeMethod<String>('startSpeechRecognition');
  } catch (_) {
    return null;
  }
}

// ─── Root screen ────────────────────────────────────────────────────────────

class ExpenseWatchScreen extends StatelessWidget {
  const ExpenseWatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<WatchExpenseController>(
      create: (_) => WatchExpenseController()..initialize(),
      child: WatchShape(
        builder: (context, shape, child) {
          return AmbientMode(
            builder: (context, mode, child) {
              return _ExpenseWatchShell(
                shape: shape,
                isAmbient: mode != WearMode.active,
              );
            },
          );
        },
      ),
    );
  }
}

// ─── Controller ─────────────────────────────────────────────────────────────

class WatchExpenseController extends ChangeNotifier {
  static final DateFormat _timeFormatter = DateFormat('HH:mm');

  late final ValueListenable<Box<ExpenseModel>> _expensesListenable;
  bool _isInitialized = false;
  bool _isSaving = false;
  bool _isRefreshing = false;
  List<ExpenseModel> _recentExpenses = const <ExpenseModel>[];

  List<ExpenseModel> get recentExpenses => _recentExpenses;
  bool get isSaving => _isSaving;
  bool get isRefreshing => _isRefreshing;

  int? get currentUserId {
    final signedInUserId = AuthMemoryStore.currentUserId;
    if (signedInUserId != null) return signedInUserId;
    return WearExpenseSyncService.instance.effectiveUserId;
  }

  bool get hasSyncedPhoneData =>
      WearExpenseSyncService.instance.syncedUserId != null;

  bool get canCreateExpense => currentUserId != null;

  void initialize() {
    if (_isInitialized) return;
    _expensesListenable = LocalStorageService.expensesListenable;
    _expensesListenable.addListener(_refreshExpenses);
    _refreshExpenses();
    _isInitialized = true;
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _expensesListenable.removeListener(_refreshExpenses);
    }
    super.dispose();
  }

  Future<void> requestSync() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    notifyListeners();
    try {
      await WearExpenseSyncService.instance.requestRecentExpenses();
      await Future<void>.delayed(const Duration(milliseconds: 650));
      _refreshExpenses();
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> addQuickExpense({
    required String name,
    required WatchQuickCategory category,
    required String rawAmount,
  }) async {
    final resolvedUserId = currentUserId;
    final normalizedAmount = rawAmount.replaceAll(RegExp(r'[^0-9]'), '');
    final amount = double.tryParse(normalizedAmount);
    if (resolvedUserId == null || amount == null || amount <= 0 || _isSaving) {
      return;
    }

    final now = DateTime.now();
    final expense = ExpenseModel()
      ..userId = resolvedUserId
      ..name = name.trim().isEmpty ? category.label : name.trim()
      ..amount = amount
      ..date = now
      ..time = _timeFormatter.format(now)
      ..source = 'WEAR_QUICK_ADD'
      ..createdAt = now
      ..primaryCategory = category.primaryCategory
      ..detailLabels = <String>[category.label];

    _isSaving = true;
    notifyListeners();
    try {
      await LocalStorageService.expenseBox.add(expense);
      _refreshExpenses();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> editExpense({
    required ExpenseModel original,
    required String name,
    required WatchQuickCategory category,
    required String rawAmount,
  }) async {
    final normalizedAmount = rawAmount.replaceAll(RegExp(r'[^0-9]'), '');
    final amount = double.tryParse(normalizedAmount);
    if (amount == null || amount <= 0 || _isSaving) return;
    final key = original.key;
    if (key == null) return;

    final updated = ExpenseModel()
      ..userId = original.userId
      ..name = name.trim().isEmpty ? category.label : name.trim()
      ..amount = amount
      ..date = original.date
      ..time = original.time
      ..source = original.source
      ..createdAt = original.createdAt
      ..primaryCategory = category.primaryCategory
      ..detailLabels = <String>[category.label];

    _isSaving = true;
    notifyListeners();
    try {
      await LocalStorageService.expenseBox.put(key, updated);
      _refreshExpenses();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void _refreshExpenses() {
    final resolvedUserId = currentUserId;
    final visibleExpenses = LocalStorageService.expenseBox.values
        .where(
          (expense) =>
              resolvedUserId == null || expense.userId == resolvedUserId,
        )
        .toList()
      ..sort(
        (left, right) =>
            _expenseDateTime(right).compareTo(_expenseDateTime(left)),
      );
    _recentExpenses = visibleExpenses.take(5).toList(growable: false);
    notifyListeners();
  }

  DateTime _expenseDateTime(ExpenseModel expense) {
    final parsedTime = AppTimeFormatService.parseHourMinute(expense.time);
    return DateTime(
      expense.date.year,
      expense.date.month,
      expense.date.day,
      parsedTime.hour,
      parsedTime.minute,
    );
  }
}

// ─── Shell ───────────────────────────────────────────────────────────────────

class _ExpenseWatchShell extends StatelessWidget {
  const _ExpenseWatchShell({required this.shape, required this.isAmbient});

  final WearShape shape;
  final bool isAmbient;

  bool get _isRound => shape == WearShape.round;

  @override
  Widget build(BuildContext context) {
    return Consumer<WatchExpenseController>(
      builder: (context, controller, child) {
        return Theme(
          data: _buildWatchTheme(),
          child: Scaffold(
            backgroundColor: isAmbient ? Colors.black : Colors.white,
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerFloat,
            floatingActionButton: isAmbient
                ? null
                : _WatchQuickAddButton(controller: controller),
            body: Column(
              children: [
                // Pinned header — never scrolls
                _WatchHeader(
                  isAmbient: isAmbient,
                  isRefreshing: controller.isRefreshing,
                  isRound: _isRound,
                ),
                const SizedBox(height: 6),
                Text(
                  controller.isRefreshing
                      ? 'Syncing...'
                      : (isAmbient ? 'Ambient' : 'Pull to sync'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isAmbient ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                // Scrollable content
                Expanded(
                  child: RefreshIndicator(
                    color: Colors.white,
                    backgroundColor: AppPalette.green,
                    onRefresh: controller.requestSync,
                    child: !controller.hasSyncedPhoneData
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            children: [
                              _WatchSyncState(
                                isRefreshing: controller.isRefreshing,
                                onRefresh: controller.requestSync,
                              ),
                            ],
                          )
                        : controller.recentExpenses.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            children: const [_WatchEmptyState()],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: EdgeInsets.fromLTRB(
                              _isRound ? 22 : 18,
                              6,
                              _isRound ? 22 : 18,
                              98,
                            ),
                            itemCount: controller.recentExpenses.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _WatchExpenseTile(
                                  expense: controller.recentExpenses[index],
                                  isAmbient: isAmbient,
                                  controller: controller,
                                ),
                              );
                            },
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

  ThemeData _buildWatchTheme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: const ColorScheme.light(
        primary: AppPalette.green,
        secondary: AppPalette.green,
        surface: Colors.white,
        onSurface: AppPalette.ink,
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.nunitoTextTheme(base.textTheme).copyWith(
        headlineSmall: GoogleFonts.nunito(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppPalette.ink,
        ),
        titleMedium: GoogleFonts.nunito(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppPalette.ink,
        ),
      ),
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _WatchHeader extends StatelessWidget {
  const _WatchHeader({
    required this.isAmbient,
    required this.isRefreshing,
    required this.isRound,
  });

  final bool isAmbient;
  final bool isRefreshing;
  final bool isRound;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isRound ? 24 : 18,
        isRound ? 52 : 38,
        isRound ? 24 : 18,
        28,
      ),
      decoration: BoxDecoration(
        color: isAmbient ? Colors.black : AppPalette.green,
        border: isAmbient
            ? Border.all(color: Colors.white24, width: 1)
            : null,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(isRound ? 54 : 30),
          bottomRight: Radius.circular(isRound ? 54 : 30),
        ),
      ),
      child: Text(
        'Recent\nexpenses',
        textAlign: TextAlign.center,
        style: GoogleFonts.nunito(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: isAmbient ? Colors.white : AppPalette.ink,
          height: 1.2,
        ),
      ),
    );
  }
}

// ─── Detail screen header (New expense / Edit / Choose label) ────────────────

class _WatchDetailHeader extends StatelessWidget {
  const _WatchDetailHeader({required this.title, required this.isRound});

  final String title;
  final bool isRound;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isRound ? 24 : 18,
        isRound ? 42 : 30,
        isRound ? 24 : 18,
        18,
      ),
      decoration: BoxDecoration(
        color: AppPalette.green,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(isRound ? 40 : 24),
          bottomRight: Radius.circular(isRound ? 40 : 24),
        ),
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 2,
        style: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppPalette.ink,
          height: 1.2,
        ),
      ),
    );
  }
}

// ─── Sync / empty states ─────────────────────────────────────────────────────

class _WatchSyncState extends StatelessWidget {
  const _WatchSyncState({required this.isRefreshing, required this.onRefresh});

  final bool isRefreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Phone sync needed',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppPalette.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Open SpendAnt on your phone and keep both apps awake. Then pull down or retry.',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: isRefreshing ? null : onRefresh,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.green,
                  foregroundColor: AppPalette.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  isRefreshing ? 'Syncing...' : 'Retry sync',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
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

class _WatchEmptyState extends StatelessWidget {
  const _WatchEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Text(
          'No expenses yet.\nPull down or tap +.',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

// ─── Expense tile ─────────────────────────────────────────────────────────────

class _WatchExpenseTile extends StatelessWidget {
  const _WatchExpenseTile({
    required this.expense,
    required this.isAmbient,
    required this.controller,
  });

  final ExpenseModel expense;
  final bool isAmbient;
  final WatchExpenseController controller;

  static final DateFormat _shortDateFormatter = DateFormat('dd MMM');

  @override
  Widget build(BuildContext context) {
    final categoryLabel = _categoryLabel(expense);
    final amount = AppCurrencyFormatService.formatCOP(expense.amount);
    final dateLabel = _shortDateFormatter.format(expense.date);

    final tile = Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isAmbient ? Colors.black : AppPalette.field,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isAmbient ? Colors.white24 : AppPalette.green,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  expense.name.trim().isEmpty ? categoryLabel : expense.name.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isAmbient ? Colors.white : AppPalette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$categoryLabel · $dateLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isAmbient ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount,
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isAmbient ? Colors.white : AppPalette.ink,
            ),
          ),
        ],
      ),
    );

    if (isAmbient) return tile;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () async {
          final shape = context.findAncestorWidgetOfExactType<_ExpenseWatchShell>()?.shape
              ?? WearShape.round;
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => ChangeNotifierProvider.value(
                value: controller,
                child: _WatchEditScreen(expense: expense, shape: shape),
              ),
            ),
          );
        },
        child: tile,
      ),
    );
  }

  String _categoryLabel(ExpenseModel expense) {
    final labels = expense.detailLabels
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (labels.isNotEmpty) return labels.first;
    final pc = expense.primaryCategory?.trim();
    if (pc != null && pc.isNotEmpty) return pc;
    return 'Expense';
  }
}

// ─── FAB ─────────────────────────────────────────────────────────────────────

class _WatchQuickAddButton extends StatelessWidget {
  const _WatchQuickAddButton({required this.controller});

  final WatchExpenseController controller;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'watch-quick-expense-fab',
      backgroundColor: AppPalette.green,
      foregroundColor: AppPalette.ink,
      onPressed: controller.isSaving || !controller.canCreateExpense
          ? null
          : () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: controller,
                    child: const _WatchQuickAddScreen(),
                  ),
                ),
              );
            },
      child: controller.isSaving
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppPalette.ink,
              ),
            )
          : const Icon(Icons.add_rounded, size: 28),
    );
  }
}

// ─── New expense screen ───────────────────────────────────────────────────────

class _WatchQuickAddScreen extends StatefulWidget {
  const _WatchQuickAddScreen();

  @override
  State<_WatchQuickAddScreen> createState() => _WatchQuickAddScreenState();
}

class _WatchQuickAddScreenState extends State<_WatchQuickAddScreen> {
  final TextEditingController _nameController = TextEditingController();
  String _amountDigits = '';
  WatchQuickCategory _selectedCategory = watchQuickCategories.first;
  bool _isLoadingVoice = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final selected = await Navigator.of(context).push<WatchQuickCategory>(
      MaterialPageRoute<WatchQuickCategory>(
        builder: (_) => _WatchCategoryPickerScreen(
          selectedCategory: _selectedCategory,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedCategory = selected);
  }

  Future<void> _activateVoice() async {
    setState(() => _isLoadingVoice = true);
    try {
      final result = await _startVoiceInput();
      if (result != null && result.isNotEmpty && mounted) {
        setState(() => _nameController.text = result);
      }
    } finally {
      if (mounted) setState(() => _isLoadingVoice = false);
    }
  }

  Future<void> _save() async {
    if (_amountDigits.isEmpty) return;
    final controller = context.read<WatchExpenseController>();
    await controller.addQuickExpense(
      name: _nameController.text.trim(),
      category: _selectedCategory,
      rawAmount: _amountDigits,
    );
    if (mounted) Navigator.of(context).pop();
  }

  void _appendDigit(String digit) {
    setState(() {
      if (_amountDigits.length >= 7) return;
      _amountDigits = '$_amountDigits$digit';
    });
  }

  void _deleteDigit() {
    if (_amountDigits.isEmpty) return;
    setState(() {
      _amountDigits = _amountDigits.substring(0, _amountDigits.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WatchExpenseController>();
    final formattedAmount = _amountDigits.isEmpty
        ? '0'
        : AppCurrencyFormatService.formatAmount(double.parse(_amountDigits));
    final isRound = MediaQuery.of(context).size.width ==
        MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _WatchDetailHeader(title: 'New\nexpense', isRound: isRound),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
              child: Column(
                children: [
                  _WatchFieldCard(
                    label: 'Amount',
                    child: Column(
                      children: [
                        Text(
                          formattedAmount,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.ink,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _WatchNumberPad(
                          onDigitTap: _appendDigit,
                          onBackspaceTap: _deleteDigit,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _WatchFieldCard(
                    label: 'Name',
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            textAlign: TextAlign.center,
                            textInputAction: TextInputAction.done,
                            style: GoogleFonts.nunito(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.ink,
                            ),
                            decoration:
                                _watchInputDecoration(_selectedCategory.label),
                          ),
                        ),
                        IconButton(
                          onPressed: _isLoadingVoice ? null : _activateVoice,
                          icon: _isLoadingVoice
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppPalette.green,
                                  ),
                                )
                              : const Icon(
                                  Icons.mic_rounded,
                                  color: AppPalette.green,
                                  size: 22,
                                ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _WatchActionCard(
                    label: 'Category',
                    assetPath: _selectedCategory.assetPath,
                    value: _selectedCategory.label,
                    onTap: _pickCategory,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: controller.canCreateExpense &&
                              !controller.isSaving &&
                              _amountDigits.isNotEmpty
                          ? _save
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppPalette.green,
                        foregroundColor: AppPalette.ink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        controller.isSaving ? 'Saving...' : 'Save expense',
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
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
    );
  }
}

// ─── Edit expense screen ──────────────────────────────────────────────────────

class _WatchEditScreen extends StatefulWidget {
  const _WatchEditScreen({required this.expense, required this.shape});

  final ExpenseModel expense;
  final WearShape shape;

  @override
  State<_WatchEditScreen> createState() => _WatchEditScreenState();
}

class _WatchEditScreenState extends State<_WatchEditScreen> {
  late final TextEditingController _nameController;
  late String _amountDigits;
  late WatchQuickCategory _selectedCategory;
  bool _isLoadingVoice = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.expense.name.trim());
    _amountDigits = widget.expense.amount.round().toString();
    _selectedCategory = _categoryFromExpense(widget.expense);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  WatchQuickCategory _categoryFromExpense(ExpenseModel expense) {
    final label = expense.detailLabels.isEmpty
        ? (expense.primaryCategory ?? '')
        : expense.detailLabels.first;
    return watchQuickCategories.firstWhere(
      (c) => c.label == label || c.primaryCategory == expense.primaryCategory,
      orElse: () => watchQuickCategories.first,
    );
  }

  Future<void> _pickCategory() async {
    final selected = await Navigator.of(context).push<WatchQuickCategory>(
      MaterialPageRoute<WatchQuickCategory>(
        builder: (_) => _WatchCategoryPickerScreen(
          selectedCategory: _selectedCategory,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedCategory = selected);
  }

  Future<void> _activateVoice() async {
    setState(() => _isLoadingVoice = true);
    try {
      final result = await _startVoiceInput();
      if (result != null && result.isNotEmpty && mounted) {
        setState(() => _nameController.text = result);
      }
    } finally {
      if (mounted) setState(() => _isLoadingVoice = false);
    }
  }

  Future<void> _save() async {
    if (_amountDigits.isEmpty) return;
    final controller = context.read<WatchExpenseController>();
    await controller.editExpense(
      original: widget.expense,
      name: _nameController.text.trim(),
      category: _selectedCategory,
      rawAmount: _amountDigits,
    );
    if (mounted) Navigator.of(context).pop();
  }

  void _appendDigit(String digit) {
    setState(() {
      if (_amountDigits.length >= 7) return;
      _amountDigits = '$_amountDigits$digit';
    });
  }

  void _deleteDigit() {
    if (_amountDigits.isEmpty) return;
    setState(() {
      _amountDigits = _amountDigits.substring(0, _amountDigits.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WatchExpenseController>();
    final formattedAmount = _amountDigits.isEmpty
        ? '0'
        : AppCurrencyFormatService.formatAmount(double.parse(_amountDigits));
    final isRound = widget.shape == WearShape.round;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _WatchDetailHeader(title: 'Edit\nexpense', isRound: isRound),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
              child: Column(
                children: [
                  _WatchFieldCard(
                    label: 'Amount',
                    child: Column(
                      children: [
                        Text(
                          formattedAmount,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.ink,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _WatchNumberPad(
                          onDigitTap: _appendDigit,
                          onBackspaceTap: _deleteDigit,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _WatchFieldCard(
                    label: 'Name',
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            textAlign: TextAlign.center,
                            textInputAction: TextInputAction.done,
                            style: GoogleFonts.nunito(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.ink,
                            ),
                            decoration:
                                _watchInputDecoration(_selectedCategory.label),
                          ),
                        ),
                        IconButton(
                          onPressed: _isLoadingVoice ? null : _activateVoice,
                          icon: _isLoadingVoice
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppPalette.green,
                                  ),
                                )
                              : const Icon(
                                  Icons.mic_rounded,
                                  color: AppPalette.green,
                                  size: 22,
                                ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _WatchActionCard(
                    label: 'Category',
                    assetPath: _selectedCategory.assetPath,
                    value: _selectedCategory.label,
                    onTap: _pickCategory,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: !controller.isSaving && _amountDigits.isNotEmpty
                          ? _save
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppPalette.green,
                        foregroundColor: AppPalette.ink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        controller.isSaving ? 'Saving...' : 'Save changes',
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
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
    );
  }
}

// ─── Category picker screen ───────────────────────────────────────────────────

class _WatchCategoryPickerScreen extends StatelessWidget {
  const _WatchCategoryPickerScreen({required this.selectedCategory});

  final WatchQuickCategory selectedCategory;

  @override
  Widget build(BuildContext context) {
    final isRound = MediaQuery.of(context).size.width ==
        MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _WatchDetailHeader(title: 'Choose\nlabel', isRound: isRound),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
              itemCount: watchQuickCategories.length,
              itemBuilder: (context, index) {
                final category = watchQuickCategories[index];
                final isSelected = category == selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _WatchCategoryListTile(
                    category: category,
                    isSelected: isSelected,
                    onTap: () => Navigator.of(context).pop(category),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared form widgets ──────────────────────────────────────────────────────

class _WatchFieldCard extends StatelessWidget {
  const _WatchFieldCard({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppPalette.field,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppPalette.green),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _WatchActionCard extends StatelessWidget {
  const _WatchActionCard({
    required this.label,
    required this.value,
    required this.assetPath,
    required this.onTap,
  });

  final String label;
  final String value;
  final String assetPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: AppPalette.field,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppPalette.green),
          ),
          child: Column(
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 6),
              SvgPicture.asset(assetPath, width: 24, height: 24),
              const SizedBox(height: 6),
              Text(
                value,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
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

class _WatchCategoryListTile extends StatelessWidget {
  const _WatchCategoryListTile({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final WatchQuickCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppPalette.green : AppPalette.field,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              SvgPicture.asset(category.assetPath, width: 20, height: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.label,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.ink,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_rounded, color: AppPalette.ink, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Number pad ───────────────────────────────────────────────────────────────

class _WatchNumberPad extends StatelessWidget {
  const _WatchNumberPad({
    required this.onDigitTap,
    required this.onBackspaceTap,
  });

  final ValueChanged<String> onDigitTap;
  final VoidCallback onBackspaceTap;

  @override
  Widget build(BuildContext context) {
    const rows = <List<String>>[
      <String>['1', '2', '3'],
      <String>['4', '5', '6'],
      <String>['7', '8', '9'],
      <String>['00', '0', '<'],
    ];

    return Column(
      children: [
        for (final row in rows)
          Row(
            children: [
              for (final key in row)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: SizedBox(
                      height: 36,
                      child: ElevatedButton(
                        onPressed: key == '<'
                            ? onBackspaceTap
                            : () => onDigitTap(key),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppPalette.green,
                          foregroundColor: AppPalette.ink,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: key == '<'
                            ? const Icon(Icons.backspace_outlined, size: 16)
                            : Text(
                                key,
                                style: GoogleFonts.nunito(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

InputDecoration _watchInputDecoration(String hintText) {
  return InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    hintText: hintText,
    hintStyle: GoogleFonts.nunito(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: Colors.black38,
    ),
    border: InputBorder.none,
  );
}

// ─── Category data ────────────────────────────────────────────────────────────

class WatchQuickCategory {
  const WatchQuickCategory({
    required this.label,
    required this.shortLabel,
    required this.primaryCategory,
    required this.assetPath,
  });

  final String label;
  final String shortLabel;
  final String primaryCategory;
  final String assetPath;
}

const List<WatchQuickCategory> watchQuickCategories = <WatchQuickCategory>[
  WatchQuickCategory(label: 'University Fees', shortLabel: 'Fees', primaryCategory: 'Services', assetPath: 'web/icons/UniversityFees.svg'),
  WatchQuickCategory(label: 'Learning Materials', shortLabel: 'Books', primaryCategory: 'Services', assetPath: 'web/icons/LearningMaterials.svg'),
  WatchQuickCategory(label: 'Commute', shortLabel: 'Commute', primaryCategory: 'Transport', assetPath: 'web/icons/Commute.svg'),
  WatchQuickCategory(label: 'Food', shortLabel: 'Food', primaryCategory: 'Food', assetPath: 'web/icons/Food.svg'),
  WatchQuickCategory(label: 'Group Hangouts', shortLabel: 'Friends', primaryCategory: 'Other', assetPath: 'web/icons/GroupHangouts.svg'),
  WatchQuickCategory(label: 'Food Delivery', shortLabel: 'Delivery', primaryCategory: 'Food', assetPath: 'web/icons/FoodDelivery.svg'),
  WatchQuickCategory(label: 'Entertainment', shortLabel: 'Fun', primaryCategory: 'Other', assetPath: 'web/icons/Entertaiment.svg'),
  WatchQuickCategory(label: 'Subscriptions', shortLabel: 'Subs', primaryCategory: 'Other', assetPath: 'web/icons/Subscriptions.svg'),
  WatchQuickCategory(label: 'Gifts', shortLabel: 'Gifts', primaryCategory: 'Other', assetPath: 'web/icons/Gifts.svg'),
  WatchQuickCategory(label: 'Rent', shortLabel: 'Rent', primaryCategory: 'Services', assetPath: 'web/icons/Rent.svg'),
  WatchQuickCategory(label: 'Utilities', shortLabel: 'Bills', primaryCategory: 'Services', assetPath: 'web/icons/Utilities.svg'),
  WatchQuickCategory(label: 'Services', shortLabel: 'Svc', primaryCategory: 'Services', assetPath: 'web/icons/Services.svg'),
  WatchQuickCategory(label: 'Groceries', shortLabel: 'Grocery', primaryCategory: 'Food', assetPath: 'web/icons/Groceries.svg'),
  WatchQuickCategory(label: 'Personal Care', shortLabel: 'Care', primaryCategory: 'Other', assetPath: 'web/icons/PersonalCare.svg'),
  WatchQuickCategory(label: 'Transport', shortLabel: 'Transport', primaryCategory: 'Transport', assetPath: 'web/icons/Transport.svg'),
  WatchQuickCategory(label: 'Owed', shortLabel: 'Owed', primaryCategory: 'Other', assetPath: 'web/icons/Owed.svg'),
  WatchQuickCategory(label: 'Impulse', shortLabel: 'Impulse', primaryCategory: 'Other', assetPath: 'web/icons/Impulse.svg'),
  WatchQuickCategory(label: 'Emergency', shortLabel: 'Emergency', primaryCategory: 'Other', assetPath: 'web/icons/Emergency.svg'),
];
