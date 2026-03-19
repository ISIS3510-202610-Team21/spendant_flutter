import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app.dart';
import '../models/goal_model.dart';
import '../services/auth_memory_store.dart';
import '../services/cloud_sync_service.dart';
import '../services/daily_budget_service.dart';
import '../services/local_storage_service.dart';
import '../theme/spendant_theme.dart';
import '../widgets/auth_chrome.dart';
import '../widgets/spendant_bottom_nav.dart';
import 'edit_profile_screen.dart';
import 'new_expense_screen.dart';

class SetGoalScreen extends StatefulWidget {
  const SetGoalScreen({super.key});

  @override
  State<SetGoalScreen> createState() => _SetGoalScreenState();
}

class _SetGoalScreenState extends State<SetGoalScreen> {
  static const int _defaultUserId = 1;
  static final NumberFormat _currencyFormat = NumberFormat('#,###', 'en_US');

  int _currentStep = -1;
  int _viewState = 0;
  bool _didLoadInitialView = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  DateTime _goalDeadline = DateTime.now().add(const Duration(days: 30));
  bool _isSavingGoal = false;
  String _profileName = 'John Doe';
  String _profileHandle = '@johndoe';

  @override
  void initState() {
    super.initState();
    _loadProfileIdentity();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_didLoadInitialView) {
      return;
    }

    final initialView = ModalRoute.of(context)?.settings.arguments as int?;
    if (initialView != null) {
      _viewState = initialView;
    }
    _didLoadInitialView = true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileIdentity() async {
    final authState = await AuthMemoryStore.loadGreetingState();
    final rawName = authState.username?.trim();
    final displayName = rawName == null || rawName.isEmpty
        ? 'John Doe'
        : rawName;

    if (!mounted) {
      return;
    }

    setState(() {
      _profileName = displayName;
      _profileHandle = _buildHandle(displayName);
    });
  }

  String _buildHandle(String name) {
    final normalized = name.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '',
    );
    final safeValue = normalized.isEmpty ? 'spendant' : normalized;
    return '@$safeValue';
  }

  Future<void> _openProfileEditor() async {
    final updatedName = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(initialName: _profileName),
      ),
    );

    if (updatedName == null || !mounted) {
      return;
    }

    final trimmedName = updatedName.trim();
    if (trimmedName.isEmpty) {
      return;
    }

    await AuthMemoryStore.saveLogin(trimmedName);
    if (!mounted) {
      return;
    }

    setState(() {
      _profileName = trimmedName;
      _profileHandle = _buildHandle(trimmedName);
    });
    _showMessage('Profile updated');
  }

  void _startGoalSetup() {
    FocusScope.of(context).unfocus();

    final summary = _budgetSummary();
    if (!summary.hasIncome) {
      _showMessage('Add an income first so we can calculate your daily budget');
      return;
    }

    _resetGoalForm();
    setState(() {
      _currentStep = 0;
    });
  }

  void _closeGoalSetup() {
    FocusScope.of(context).unfocus();
    setState(() {
      _currentStep = -1;
    });
  }

  void _resetGoalForm() {
    _nameController.clear();
    _amountController.clear();
    _goalDeadline = DateTime.now().add(const Duration(days: 30));
  }

  double? _parsedGoalAmount() {
    final amountText = _amountController.text.replaceAll(',', '').trim();
    return double.tryParse(amountText);
  }

  DailyBudgetSummary _budgetSummary() {
    return DailyBudgetService.buildSummaryForUser(_defaultUserId);
  }

  GoalBudgetValidationResult? _goalValidation() {
    final amount = _parsedGoalAmount();
    if (amount == null || amount <= 0) {
      return null;
    }

    return DailyBudgetService.validateNewGoal(
      userId: _defaultUserId,
      targetAmount: amount,
      currentAmount: 0,
      deadline: _goalDeadline,
    );
  }

  String _formatCop(double amount) {
    return 'COP ${_currencyFormat.format(amount.round())}';
  }

  void _showGoalBudgetValidationMessage(GoalBudgetValidationResult validation) {
    if (!validation.hasIncome) {
      _showMessage('Add an income first so we can calculate your daily budget');
      return;
    }

    if (!validation.goalFitsOnItsOwn) {
      _showMessage(
        'This goal needs about ${_formatCop(validation.dailyGoalAmount)} per day, but your internal daily budget is only ${_formatCop(validation.availableInternalDailyBudget)}.',
      );
      return;
    }

    final remainingGoalRoom =
        validation.availableInternalDailyBudget -
        validation.currentGoalDailyCommitment;
    _showMessage(
      'This goal would push your daily goal commitments to ${_formatCop(validation.projectedGoalDailyCommitment)}. You only have ${_formatCop(remainingGoalRoom)} left for new goals.',
    );
  }

  Future<void> _continueGoalSetup() async {
    FocusScope.of(context).unfocus();

    if (_currentStep == 0) {
      if (_nameController.text.trim().isEmpty) {
        _showMessage('Please enter a goal name');
        return;
      }
    } else if (_currentStep == 1) {
      final amount = _parsedGoalAmount();
      if (amount == null || amount <= 0) {
        _showMessage('Please enter a valid target amount');
        return;
      }
    } else if (_currentStep == 2) {
      final today = DateUtils.dateOnly(DateTime.now());
      if (DateUtils.dateOnly(_goalDeadline).isBefore(today)) {
        _showMessage('Please choose a deadline from today onward');
        return;
      }

      final validation = _goalValidation();
      if (validation == null || !validation.canCreateGoal) {
        if (validation != null) {
          _showGoalBudgetValidationMessage(validation);
        }
        return;
      }
    }

    setState(() {
      _currentStep++;
    });
  }

  Future<void> _finishGoalSetup() async {
    if (_isSavingGoal) {
      return;
    }

    FocusScope.of(context).unfocus();

    final amount = _parsedGoalAmount();
    if (_nameController.text.trim().isEmpty || amount == null || amount <= 0) {
      _showMessage('Please complete all fields');
      return;
    }

    final today = DateUtils.dateOnly(DateTime.now());
    if (DateUtils.dateOnly(_goalDeadline).isBefore(today)) {
      _showMessage('Please choose a valid deadline');
      return;
    }

    final validation = _goalValidation();
    if (validation == null || !validation.canCreateGoal) {
      if (validation != null) {
        _showGoalBudgetValidationMessage(validation);
      }
      return;
    }

    setState(() {
      _isSavingGoal = true;
    });

    final goal = GoalModel()
      ..userId = _defaultUserId
      ..name = _nameController.text.trim()
      ..targetAmount = amount
      ..currentAmount = 0
      ..deadline = _goalDeadline
      ..isCompleted = false
      ..createdAt = DateTime.now()
      ..isSynced = false;

    try {
      await LocalStorageService().saveGoal(goal);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingGoal = false;
      });
      _showMessage('The goal could not be saved');
      return;
    }

    if (!mounted) {
      return;
    }

    _resetGoalForm();
    setState(() {
      _isSavingGoal = false;
      _currentStep = -1;
      _viewState = 1;
    });
    _showMessage('Goal saved locally');
    _syncPendingDataInBackground();
  }

  void _syncPendingDataInBackground() {
    unawaited(_runPendingCloudSync());
  }

  Future<void> _runPendingCloudSync() async {
    try {
      await CloudSyncService().syncAllPendingData();
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage('Goal saved locally. Cloud sync is still pending');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_currentStep >= 0) {
      return Scaffold(
        backgroundColor: AppPalette.amber,
        body: _buildGoalSetupFlow(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: _viewState == 0 ? _buildProfileView() : _buildGoalsView(),
          ),
          SpendAntBottomNav(
            currentItem: _viewState == 0
                ? SpendAntNavItem.profile
                : SpendAntNavItem.goals,
            onProfileTap: () => setState(() => _viewState = 0),
            onGoalsTap: () => setState(() => _viewState = 1),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileView() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 58, 20, 34),
          decoration: const BoxDecoration(
            color: AppPalette.green,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 32, height: 32),
                  Expanded(
                    child: Text(
                      'Profile',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _openProfileEditor,
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: AppPalette.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const CircleAvatar(
                radius: 40,
                backgroundColor: Color(0xFFFFCCBB),
                child: Icon(Icons.person, color: Color(0xFFFF9999), size: 45),
              ),
              const SizedBox(height: 12),
              Text(
                _profileName,
                style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                _profileHandle,
                style: GoogleFonts.nunito(fontSize: 14, color: Colors.black54),
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _profileActionButton(
              'Income',
              Icons.attach_money,
              isIncomeBtn: true,
            ),
            const SizedBox(width: 16),
            _profileActionButton('Goals', Icons.flag_outlined, isGoalBtn: true),
          ],
        ),
        const SizedBox(height: 14),
        Center(
          child: _profileActionButton(
            'Set Bank Account',
            Icons.account_balance_outlined,
          ),
        ),
        const Spacer(),
        const Center(
          child: SizedBox(
            width: 150,
            height: 180,
            child: AntAsset('web/ant/Standing.svg'),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _profileActionButton(
    String label,
    IconData icon, {
    bool isGoalBtn = false,
    bool isIncomeBtn = false,
  }) {
    return ElevatedButton.icon(
      onPressed: () {
        if (isGoalBtn) {
          setState(() => _viewState = 1);
        } else if (isIncomeBtn) {
          Navigator.of(context).pushNamed(AppRoutes.budget);
        }
      },
      icon: Icon(icon, size: 20, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  Widget _buildGoalsView() {
    final budgetDependencies = Listenable.merge(<Listenable>[
      LocalStorageService.goalsListenable,
      LocalStorageService.incomesListenable,
      LocalStorageService.expensesListenable,
    ]);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => setState(() => _viewState = 0),
                    icon: const Icon(
                      Icons.close,
                      size: 28,
                      color: Colors.black,
                    ),
                  ),
                ),
                Text(
                  'Goals',
                  style: GoogleFonts.nunito(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: budgetDependencies,
              builder: (context, _) {
                final box = LocalStorageService.goalBox;
                final goals =
                    box.values
                        .where((goal) => goal.userId == _defaultUserId)
                        .toList()
                      ..sort(
                        (left, right) =>
                            right.createdAt.compareTo(left.createdAt),
                      );
                final summary = _budgetSummary();
                final canCreateGoal = summary.hasIncome;

                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _GoalBudgetCard(
                      summary: summary,
                      currencyFormat: _currencyFormat,
                    ),
                    const SizedBox(height: 14),
                    if (!summary.hasIncome) ...[
                      const _GoalRulesNotice(
                        message:
                            'Goals need at least one active income because every goal reserves part of your daily budget.',
                      ),
                      const SizedBox(height: 14),
                    ] else if (summary.isSpendableBudgetExhausted) ...[
                      _GoalRulesNotice(
                        message: summary.isInternalBudgetExhausted
                            ? 'You already spent all of today\'s internal budget. Your goals cannot grow from today\'s money anymore.'
                            : 'You already spent all the money available to spend today. Spending more will start affecting the money reserved for your goals.',
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (goals.isEmpty) const _EmptyGoalsCard(),
                    for (final goal in goals) _GoalTile(goal: goal),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      onPressed: canCreateGoal
                          ? _startGoalSetup
                          : () => Navigator.of(
                              context,
                            ).pushNamed(AppRoutes.budget),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: Text(
                        canCreateGoal ? 'New Goal' : 'Add Income First',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalSetupFlow() {
    switch (_currentStep) {
      case 0:
        return _setupStepLayout(
          'What are you saving for?',
          _setupTextField(_nameController, 'e.g. A new car'),
          'web/ant/Presenting.svg',
        );
      case 1:
        return _setupStepLayout(
          'How much money do you want to save?',
          _setupTextField(_amountController, '\$0', isNum: true),
          'web/ant/Standing.svg',
        );
      case 2:
        return _setupStepLayout(
          'When is the deadline?',
          _setupDatePicker(),
          'web/ant/Surprised.svg',
        );
      case 3:
        return _buildStepPlan();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _setupStepLayout(String title, Widget content, String asset) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: _isSavingGoal ? null : _closeGoalSetup,
                icon: const Icon(Icons.close, size: 30),
              ),
            ),
            const Spacer(),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 30),
            content,
            const SizedBox(height: 40),
            SizedBox(height: 150, child: AntAsset(asset)),
            const Spacer(),
            ElevatedButton(
              onPressed: _continueGoalSetup,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepPlan() {
    final amount = _parsedGoalAmount() ?? 0;
    final validation = _goalValidation();
    final summary = _budgetSummary();
    final suggestedDailySaving = validation?.dailyGoalAmount ?? 0;
    final projectedSpendableBudget = validation == null
        ? summary.spendableDailyBudget
        : validation.availableInternalDailyBudget -
              validation.projectedGoalDailyCommitment;
    final guidanceMessage = switch (validation) {
      null => null,
      GoalBudgetValidationResult(:final hasIncome) when !hasIncome =>
        'Add an income first so this goal has a real daily budget behind it.',
      GoalBudgetValidationResult(:final goalFitsOnItsOwn)
          when !goalFitsOnItsOwn =>
        'This goal alone already needs more per day than your internal budget can support.',
      GoalBudgetValidationResult(:final goalFitsWithAllGoals)
          when !goalFitsWithAllGoals =>
        'With your other goals included, this one would reserve more money per day than your income allows.',
      _ => 'This goal fits inside your internal daily budget.',
    };
    final guidanceColor = validation?.canCreateGoal == true
        ? AppPalette.green
        : Colors.black87;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: _closeGoalSetup,
                icon: const Icon(Icons.close, size: 30),
              ),
            ),
            const Spacer(),
            Text(
              '"We have a plan"',
              style: GoogleFonts.nunito(
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'To save COP ${_currencyFormat.format(amount.round())} for ${_nameController.text.trim()}, start today and aim for about COP ${_currencyFormat.format(suggestedDailySaving.round())} per day until ${DateFormat('d/M/y').format(_goalDeadline)}.',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppPalette.ink,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GoalPlanStat(
                    label: 'Internal daily budget',
                    value: _formatCop(summary.internalDailyBudget),
                  ),
                  const SizedBox(height: 8),
                  _GoalPlanStat(
                    label: 'Other goals already reserve',
                    value: _formatCop(summary.totalGoalDailyCommitment),
                  ),
                  const SizedBox(height: 8),
                  _GoalPlanStat(
                    label: 'This goal would reserve',
                    value: _formatCop(suggestedDailySaving),
                  ),
                  const SizedBox(height: 8),
                  _GoalPlanStat(
                    label: 'User daily budget after this goal',
                    value: _formatCop(projectedSpendableBudget),
                  ),
                  if (guidanceMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      guidanceMessage,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: guidanceColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 40),
            const SizedBox(height: 180, child: AntAsset('web/ant/Ok.svg')),
            const Spacer(),
            ElevatedButton(
              onPressed: _isSavingGoal || validation?.canCreateGoal != true
                  ? null
                  : _finishGoalSetup,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: Text(
                _isSavingGoal ? 'Saving...' : 'Alright!',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupTextField(
    TextEditingController controller,
    String hint, {
    bool isNum = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNum
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: isNum ? const [_GoalAmountFormatter()] : [],
      decoration: InputDecoration(
        hintText: hint,
        fillColor: Colors.white,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _setupDatePicker() {
    return GestureDetector(
      onTap: () async {
        final selected = await Navigator.of(context).push<DateTime>(
          MaterialPageRoute(
            builder: (_) => DateSelectionScreen(initialDate: _goalDeadline),
          ),
        );
        if (selected != null) {
          setState(() => _goalDeadline = selected);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          DateFormat('d/M/y').format(_goalDeadline),
          style: GoogleFonts.nunito(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppPalette.ink,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.goal});

  final GoalModel goal;

  @override
  Widget build(BuildContext context) {
    final progress = goal.getProgressPercent() / 100;
    final widthFactor = progress.clamp(0.0, 1.0).toDouble();
    final dailyReserve = DailyBudgetService.dailyGoalContribution(goal);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      height: 86,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppPalette.gray,
              borderRadius: BorderRadius.circular(25),
            ),
          ),
          FractionallySizedBox(
            widthFactor: widthFactor,
            child: Container(
              decoration: BoxDecoration(
                color: AppPalette.green.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(25),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Deadline: ${DateFormat('d/M/y').format(goal.deadline)}',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        'Saved: COP ${NumberFormat('#,###', 'en_US').format(goal.currentAmount.round())} / ${NumberFormat('#,###', 'en_US').format(goal.targetAmount.round())}',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Daily reserve: COP ${NumberFormat('#,###', 'en_US').format(dailyReserve.round())}',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${goal.getProgressPercent()}%',
                  style: GoogleFonts.nunito(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyGoalsCard extends StatelessWidget {
  const _EmptyGoalsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.field,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        'No local goals yet. Create one and it will stay available offline until you sync it.',
        textAlign: TextAlign.center,
        style: GoogleFonts.nunito(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: AppPalette.ink,
        ),
      ),
    );
  }
}

class _GoalBudgetCard extends StatelessWidget {
  const _GoalBudgetCard({required this.summary, required this.currencyFormat});

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
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily budget',
            style: GoogleFonts.nunito(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppPalette.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your incomes define the internal daily budget. Goals reserve part of it, and the rest is what you can safely spend today.',
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
                child: _GoalBudgetStat(
                  label: 'Internal',
                  value: _format(summary.internalDailyBudget),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GoalBudgetStat(
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
                child: _GoalBudgetStat(
                  label: 'User daily budget',
                  value: _format(summary.spendableDailyBudget),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GoalBudgetStat(
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

class _GoalBudgetStat extends StatelessWidget {
  const _GoalBudgetStat({required this.label, required this.value});

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

class _GoalRulesNotice extends StatelessWidget {
  const _GoalRulesNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0D9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline, color: AppPalette.ink),
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

class _GoalPlanStat extends StatelessWidget {
  const _GoalPlanStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppPalette.fieldHint,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: GoogleFonts.nunito(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: AppPalette.ink,
          ),
        ),
      ],
    );
  }
}

class _GoalAmountFormatter extends TextInputFormatter {
  const _GoalAmountFormatter();

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
