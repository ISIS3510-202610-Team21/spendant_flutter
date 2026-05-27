import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:wear/wear.dart';

import '../models/expense_model.dart';
import '../models/voice_parse_result.dart';
import '../services/app_currency_format_service.dart';
import '../services/currency_provider.dart';
import '../theme/expense_visuals.dart';
import '../services/app_time_format_service.dart';
import '../services/auth_memory_store.dart';
import '../services/local_storage_service.dart';
import '../services/voice_pipeline_service.dart';
import '../services/wear_expense_sync_service.dart';
import '../theme/spendant_theme.dart';

// ─── Voice helpers ───────────────────────────────────────────────────────────

Future<VoiceParseResult?> _listenAndParse() async {
  try {
    // Request RECORD_AUDIO at runtime — required by SpeechRecognizer on Wear OS
    // (permission is declared in the manifest but not auto-granted).
    final status = await Permission.microphone.request();
    if (!status.isGranted) return null;

    final rawText = await VoicePipelineService.startListening();
    if (rawText == null || rawText.trim().isEmpty) return null;
    return VoicePipelineService.parseAndCache(rawText);
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
              return _VoiceWatchShell(
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
  List<ExpenseCategoryTotal> _monthlyCategories = const <ExpenseCategoryTotal>[];

  List<ExpenseModel> get recentExpenses => _recentExpenses;
  List<ExpenseCategoryTotal> get monthlyCategories => _monthlyCategories;
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
    // Rebuild when active currency changes (phone syncs new currency to watch).
    CurrencyProvider.instance.addListener(notifyListeners);
    _refreshExpenses();
    _isInitialized = true;
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _expensesListenable.removeListener(_refreshExpenses);
    }
    CurrencyProvider.instance.removeListener(notifyListeners);
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
    required bool isVoice,
  }) async {
    final resolvedUserId = currentUserId;
    final normalizedAmount = rawAmount.replaceAll(RegExp(r'[^0-9]'), '');
    final localAmount = double.tryParse(normalizedAmount);
    if (resolvedUserId == null || localAmount == null || localAmount <= 0 || _isSaving) {
      return;
    }
    // _amountDigits is in the active display currency; convert to COP for storage.
    final amount = CurrencyProvider.instance.convertToCOP(localAmount);

    final now = DateTime.now();
    final expense = ExpenseModel()
      ..userId = resolvedUserId
      ..name = name.trim().isEmpty ? category.label : name.trim()
      ..amount = amount
      ..date = now
      ..time = _timeFormatter.format(now)
      ..source = isVoice ? 'WEAR_VOICE' : 'WEAR_MANUAL'
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
    final localAmount = double.tryParse(normalizedAmount);
    if (localAmount == null || localAmount <= 0 || _isSaving) return;
    final key = original.key;
    if (key == null) return;
    // _amountDigits is in the active display currency; convert to COP for storage.
    final amount = CurrencyProvider.instance.convertToCOP(localAmount);

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

    // Prefer monthly totals pushed by the phone (covers the full expense
    // history); fall back to computing from the 5 local expenses on the watch.
    final phoneCategories =
        WearExpenseSyncService.instance.storedMonthlyCategories;
    _monthlyCategories = phoneCategories.isNotEmpty
        ? phoneCategories
        : ExpenseVisuals.topCategoryTotalsForMonth(visibleExpenses, limit: 3);

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

class _VoiceWatchShell extends StatefulWidget {
  const _VoiceWatchShell({required this.shape, required this.isAmbient});

  final WearShape shape;
  final bool isAmbient;

  bool get _isRound => shape == WearShape.round;

  @override
  State<_VoiceWatchShell> createState() => _VoiceWatchShellState();
}

class _VoiceWatchShellState extends State<_VoiceWatchShell> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onRotaryScroll(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // Wear OS rotary encoder fires PointerScrollEvent with scrollDelta.dy.
    // Multiply by 50 to convert the raw rotary unit to a comfortable pixel jump.
    final delta = signal.scrollDelta.dy * 50.0;
    final target = (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _scrollController.jumpTo(target);
  }

  Color _accentColorForExpense(
    ExpenseModel expense,
    List<ExpenseCategoryTotal> monthlyCategories,
    int expenseIndex,
  ) {
    final label = expense.detailLabels
            .where((l) => l.trim().isNotEmpty)
            .firstOrNull ??
        expense.primaryCategory?.trim() ??
        '';
    for (var i = 0; i < monthlyCategories.length; i++) {
      if (monthlyCategories[i].label == label) {
        return ExpenseVisuals.reservedChartColors[i];
      }
    }
    return ExpenseVisuals.rotatingColors[
        expenseIndex % ExpenseVisuals.rotatingColors.length];
  }

  Future<void> _openAddExpense() async {
    final controller = context.read<WatchExpenseController>();
    if (!controller.canCreateExpense) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(
          value: controller,
          child: _WatchVoiceInstructionsScreen(shape: widget.shape),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WatchExpenseController>(
      builder: (context, controller, child) {
        return Theme(
          data: _buildWatchTheme(),
          child: Scaffold(
            backgroundColor: widget.isAmbient ? Colors.black : Colors.white,
            floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
            floatingActionButton: widget.isAmbient
                ? null
                : _WatchAddButton(
                    isDisabled: !controller.canCreateExpense,
                    onTap: _openAddExpense,
                  ),
            body: Column(
              children: [
                _VoiceHomeHeader(
                  isAmbient: widget.isAmbient,
                  isRound: widget._isRound,
                ),
                if (!widget.isAmbient) ...[
                  const SizedBox(height: 6),
                  Text(
                    controller.isRefreshing ? 'Syncing...' : 'Pull to sync · Tap + to add',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Expanded(
                  child: Focus(
                    autofocus: true,
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerSignal: _onRotaryScroll,
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
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: EdgeInsets.fromLTRB(
                              widget._isRound ? 22 : 18,
                              6,
                              widget._isRound ? 22 : 18,
                              98,
                            ),
                            itemCount: controller.recentExpenses.length +
                                (controller.monthlyCategories.isNotEmpty ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == 0 &&
                                  controller.monthlyCategories.isNotEmpty) {
                                return _WatchCategoryBarsSection(
                                  categories: controller.monthlyCategories,
                                );
                              }
                              final expenseIndex = controller.monthlyCategories.isNotEmpty
                                  ? index - 1
                                  : index;
                              final expense =
                                  controller.recentExpenses[expenseIndex];
                              final accentColor = _accentColorForExpense(
                                expense,
                                controller.monthlyCategories,
                                expenseIndex,
                              );
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _WatchExpenseTile(
                                  expense: expense,
                                  isAmbient: widget.isAmbient,
                                  controller: controller,
                                  accentColor: accentColor,
                                ),
                              );
                            },
                          ),
                  ),
                    ),   // Listener
                  ),     // Focus
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

// ─── Home header ─────────────────────────────────────────────────────────────

class _VoiceHomeHeader extends StatelessWidget {
  const _VoiceHomeHeader({required this.isAmbient, required this.isRound});

  final bool isAmbient;
  final bool isRound;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isRound ? 24 : 18,
        isRound ? 52 : 38,
        isRound ? 24 : 18,
        18,
      ),
      decoration: BoxDecoration(
        color: isAmbient ? Colors.black : AppPalette.green,
        border: isAmbient ? Border.all(color: Colors.white24, width: 1) : null,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(isRound ? 54 : 30),
          bottomRight: Radius.circular(isRound ? 54 : 30),
        ),
      ),
      child: Text(
        'SpendAnt',
        textAlign: TextAlign.center,
        style: GoogleFonts.nunito(
          fontSize: 16,
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

// ─── Category bars section ───────────────────────────────────────────────────

class _WatchCategoryBarsSection extends StatelessWidget {
  const _WatchCategoryBarsSection({required this.categories});

  final List<ExpenseCategoryTotal> categories;

  @override
  Widget build(BuildContext context) {
    final maxAmount = categories.first.amount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This month',
            style: GoogleFonts.nunito(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.black38,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(categories.length, (i) {
            final cat = categories[i];
            final color = ExpenseVisuals.reservedChartColors[i];
            final progress = maxAmount <= 0 ? 0.0 : cat.amount / maxAmount;
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.nunito(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        LayoutBuilder(
                          builder: (context, constraints) => Container(
                            height: 7,
                            width: constraints.maxWidth * progress,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    CurrencyProvider.instance.formatFromCOP(cat.amount),
                    style: GoogleFonts.nunito(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.ink,
                    ),
                  ),
                ],
              ),
            );
          }),
          const Divider(height: 14, color: Colors.black12),
          Text(
            'Recent expenses',
            style: GoogleFonts.nunito(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.black38,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
        ],
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
    required this.accentColor,
  });

  final ExpenseModel expense;
  final bool isAmbient;
  final WatchExpenseController controller;
  final Color accentColor;

  static final DateFormat _shortDateFormatter = DateFormat('dd MMM');

  @override
  Widget build(BuildContext context) {
    final categoryLabel = _categoryLabel(expense);
    // Display in the active currency (phone syncs its currency to the watch).
    final amount = CurrencyProvider.instance.formatFromCOP(expense.amount);
    final dateLabel = _shortDateFormatter.format(expense.date);

    final tile = ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          // Pastel tinted background matching the accent colour.
          color: isAmbient
              ? Colors.black
              : Color.lerp(accentColor, Colors.white, 0.82)!,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isAmbient
                ? Colors.white24
                : accentColor.withValues(alpha: 0.50),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Full-opacity accent left strip over the pastel background.
            if (!isAmbient)
              Container(
                width: 4,
                color: accentColor,
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            expense.name.trim().isEmpty
                                ? categoryLabel
                                : expense.name.trim(),
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
                              color:
                                  isAmbient ? Colors.white54 : Colors.black45,
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
              ),
            ),
          ],
        ),
      ),
    );

    if (isAmbient) return tile;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () async {
          final shape = context.findAncestorWidgetOfExactType<_VoiceWatchShell>()?.shape
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

// ─── Add FAB ─────────────────────────────────────────────────────────────────

class _WatchAddButton extends StatelessWidget {
  const _WatchAddButton({required this.isDisabled, required this.onTap});

  final bool isDisabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'watch-add-expense-fab',
      backgroundColor: isDisabled ? Colors.grey.shade300 : AppPalette.green,
      foregroundColor: AppPalette.ink,
      onPressed: isDisabled ? null : onTap,
      child: const Icon(Icons.add_rounded, size: 28),
    );
  }
}

// ─── Voice instructions screen ────────────────────────────────────────────────

class _WatchVoiceInstructionsScreen extends StatefulWidget {
  const _WatchVoiceInstructionsScreen({required this.shape});

  final WearShape shape;

  @override
  State<_WatchVoiceInstructionsScreen> createState() =>
      _WatchVoiceInstructionsScreenState();
}

class _WatchVoiceInstructionsScreenState
    extends State<_WatchVoiceInstructionsScreen> {
  bool _isListening = false;

  // When non-null, the voice was parsed and we're showing the "understood"
  // preview. User can confirm → navigate to full edit, or re-record.
  VoiceParseResult? _pendingResult;

  // Real-time RMS amplitude from Android SpeechRecognizer [0.0 – 1.0].
  // Exponentially smoothed to avoid jitter (same formula as phone app).
  double _amplitude = 0.0;
  StreamSubscription<double>? _rmsSub;

  @override
  void dispose() {
    _rmsSub?.cancel();
    super.dispose();
  }

  Future<void> _record() async {
    if (_isListening) return;
    setState(() {
      _isListening = true;
      _pendingResult = null;
      _amplitude = 0.0;
    });
    // Subscribe to RMS stream before startListening so no events are missed.
    _rmsSub = VoicePipelineService.rmsStream.listen((raw) {
      if (!mounted) return;
      setState(() {
        // Exponential smoothing: fast rise, slow decay for natural feel.
        _amplitude = _amplitude * 0.55 + raw * 0.45;
      });
    });
    try {
      final result = await _listenAndParse();
      if (!mounted) return;
      if (result == null) return; // no result → go back to idle
      // Show understood preview instead of navigating immediately.
      setState(() => _pendingResult = result);
    } finally {
      _rmsSub?.cancel();
      _rmsSub = null;
      if (mounted) setState(() {
        _isListening = false;
        _amplitude = 0.0;
      });
    }
  }

  Future<void> _confirmResult() async {
    final result = _pendingResult;
    if (result == null || !mounted) return;
    setState(() => _pendingResult = null);
    final controller = context.read<WatchExpenseController>();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(
          value: controller,
          child: _WatchVoiceConfirmScreen(
            parseResult: result,
            shape: widget.shape,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRound = widget.shape == WearShape.round;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _WatchDetailHeader(title: 'Add\nexpense', isRound: isRound),
          Expanded(
            child: _isListening
                ? _buildListeningView()
                : _pendingResult != null
                    ? _buildUnderstoodView(isRound)
                    : _buildIdleView(isRound),
          ),
        ],
      ),
    );
  }

  Widget _buildListeningView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Listening...',
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppPalette.ink,
            ),
          ),
          const SizedBox(height: 18),
          _SoundWaveWidget(amplitude: _amplitude),
          const SizedBox(height: 14),
          Text(
            'Speak now',
            style: GoogleFonts.nunito(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnderstoodView(bool isRound) {
    final result = _pendingResult!;
    final localAmount = CurrencyProvider.instance
        .convertToLocal(result.convertedAmountCop)
        .round();
    final amountLabel =
        '${CurrencyProvider.instance.activeCurrency} '
        '${AppCurrencyFormatService.formatAmount(localAmount.toDouble())}';
    // Truncate raw transcription so it fits on the small screen.
    final rawLabel = result.rawText.length > 42
        ? '${result.rawText.substring(0, 42)}…'
        : result.rawText;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        isRound ? 20 : 14,
        14,
        isRound ? 20 : 14,
        18,
      ),
      child: Column(
        children: [
          // Heard label
          Text(
            'I heard:',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.black38,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '"$rawLabel"',
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
              fontStyle: FontStyle.italic,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          // Parsed summary card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Color.lerp(AppPalette.green, Colors.white, 0.72)!,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppPalette.green.withValues(alpha: 0.55),
              ),
            ),
            child: Column(
              children: [
                Text(
                  amountLabel,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  result.productName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Action buttons
          Row(
            children: [
              // Re-record
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton(
                    onPressed: _record,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.ink,
                      side: const BorderSide(color: AppPalette.green),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Icon(Icons.mic_rounded, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Confirm
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: _confirmResult,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.green,
                      foregroundColor: AppPalette.ink,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Looks good',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIdleView(bool isRound) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        isRound ? 22 : 14,
        14,
        isRound ? 22 : 14,
        18,
      ),
      child: Column(
        children: [
          Text(
            'Say your expense:',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppPalette.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '"I paid [amount] for [product]"',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'e.g. "I paid 5 dollars for coffee"',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black38,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _record,
            child: Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppPalette.green,
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: AppPalette.ink,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap to record',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black45,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Voice confirm screen ─────────────────────────────────────────────────────

class _WatchVoiceConfirmScreen extends StatefulWidget {
  const _WatchVoiceConfirmScreen({
    required this.parseResult,
    required this.shape,
  });

  final VoiceParseResult parseResult;
  final WearShape shape;

  @override
  State<_WatchVoiceConfirmScreen> createState() =>
      _WatchVoiceConfirmScreenState();
}

class _WatchVoiceConfirmScreenState extends State<_WatchVoiceConfirmScreen> {
  late final TextEditingController _nameController;
  late String _amountDigits;
  late WatchQuickCategory _selectedCategory;
  bool _isLoadingVoice = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.parseResult.productName);
    // convertedAmountCop is in COP — convert to active display currency.
    _amountDigits = widget.parseResult.convertedAmountCop > 0
        ? CurrencyProvider.instance
            .convertToLocal(widget.parseResult.convertedAmountCop)
            .round()
            .toString()
        : '';
    _selectedCategory = _categoryFromName(widget.parseResult.productName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  WatchQuickCategory _categoryFromName(String name) {
    final lower = name.toLowerCase();
    for (final cat in watchQuickCategories) {
      if (lower.contains(cat.label.toLowerCase()) ||
          lower.contains(cat.shortLabel.toLowerCase())) {
        return cat;
      }
    }
    if (lower.contains('comida') ||
        lower.contains('almuerzo') ||
        lower.contains('cena') ||
        lower.contains('desayuno') ||
        lower.contains('café') ||
        lower.contains('cafe') ||
        lower.contains('restaurante')) {
      return watchQuickCategories.firstWhere(
        (c) => c.primaryCategory == 'Food',
        orElse: () => watchQuickCategories.first,
      );
    }
    if (lower.contains('transporte') ||
        lower.contains('bus') ||
        lower.contains('taxi') ||
        lower.contains('uber') ||
        lower.contains('metro')) {
      return watchQuickCategories.firstWhere(
        (c) => c.primaryCategory == 'Transport',
        orElse: () => watchQuickCategories.first,
      );
    }
    return watchQuickCategories.first;
  }

  Future<void> _reRecord() async {
    setState(() => _isLoadingVoice = true);
    try {
      final result = await _listenAndParse();
      if (result == null || !mounted) return;
      setState(() {
        _nameController.text = result.productName;
        if (result.convertedAmountCop > 0) {
          // convertedAmountCop is in COP — convert to active display currency.
          _amountDigits = CurrencyProvider.instance
              .convertToLocal(result.convertedAmountCop)
              .round()
              .toString();
        }
        _selectedCategory = _categoryFromName(result.productName);
      });
    } finally {
      if (mounted) setState(() => _isLoadingVoice = false);
    }
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

  Future<void> _save() async {
    if (_amountDigits.isEmpty) return;
    final controller = context.read<WatchExpenseController>();
    await controller.addQuickExpense(
      name: _nameController.text.trim(),
      category: _selectedCategory,
      rawAmount: _amountDigits,
      isVoice: true,
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
        : '${CurrencyProvider.instance.activeCurrency} '
            '${AppCurrencyFormatService.formatAmount(double.parse(_amountDigits))}';
    final isRound = widget.shape == WearShape.round;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _WatchDetailHeader(title: 'Confirm\nexpense', isRound: isRound),
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
                          onPressed: _isLoadingVoice ? null : _reRecord,
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
    // expense.amount is in COP — convert to active display currency.
    _amountDigits = CurrencyProvider.instance
        .convertToLocal(widget.expense.amount)
        .round()
        .toString();
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
    // Pass 1: exact label match (most specific — avoids false matches from
    // primaryCategory overlap, e.g. 'Food' matching before 'Groceries').
    final byLabel =
        watchQuickCategories.where((c) => c.label == label).firstOrNull;
    if (byLabel != null) return byLabel;
    // Pass 2: fall back to primaryCategory match.
    return watchQuickCategories.firstWhere(
      (c) => c.primaryCategory == expense.primaryCategory,
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
      final result = await _listenAndParse();
      if (result != null && mounted) {
        setState(() {
          _nameController.text = result.productName;
          if (result.convertedAmountCop > 0) {
            // convertedAmountCop is in COP — convert to active display currency.
            _amountDigits = CurrencyProvider.instance
                .convertToLocal(result.convertedAmountCop)
                .round()
                .toString();
          }
        });
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
        : '${CurrencyProvider.instance.activeCurrency} '
            '${AppCurrencyFormatService.formatAmount(double.parse(_amountDigits))}';
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

// ─── Sound wave widget ────────────────────────────────────────────────────────

/// Animated equaliser bars driven by real-time RMS amplitude.
///
/// [amplitude] is a normalized [0.0 – 1.0] value from the Android
/// SpeechRecognizer (via [VoicePipelineService.rmsStream]).  When the mic
/// is silent, [amplitude] ≈ 0 and all bars collapse to [_minHeight].
/// When voice is detected, bars rise proportionally with staggered sin
/// phases — matching the WhatsApp-style waveform on the phone app.
class _SoundWaveWidget extends StatefulWidget {
  const _SoundWaveWidget({required this.amplitude});

  /// Normalized RMS amplitude [0.0 – 1.0].  Bars are flat when 0.
  final double amplitude;

  static const int barCount = 7;

  @override
  State<_SoundWaveWidget> createState() => _SoundWaveWidgetState();
}

class _SoundWaveWidgetState extends State<_SoundWaveWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  static const double _minHeight = 5.0;
  static const double _maxHeight = 36.0;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const barWidth = 5.0;
    const gap = 4.0;

    return SizedBox(
      height: _maxHeight,
      child: AnimatedBuilder(
        animation: _waveController,
        builder: (context, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(_SoundWaveWidget.barCount, (i) {
              // Staggered sin phase per bar — same formula as phone waveform.
              final phase = i / _SoundWaveWidget.barCount * math.pi;
              final sinVal =
                  (math.sin(phase + _waveController.value * 2 * math.pi) + 1) /
                  2; // [0.0, 1.0]
              final barHeight = _minHeight +
                  sinVal * widget.amplitude * (_maxHeight - _minHeight);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: gap / 2),
                child: Container(
                  width: barWidth,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: AppPalette.green,
                    borderRadius: BorderRadius.circular(barWidth / 2),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

