import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app.dart';
import '../models/goal_model.dart';
import '../services/app_notification_service.dart';
import '../services/auth_memory_store.dart';
import '../services/cloud_sync_service.dart';
import '../services/daily_budget_service.dart';
import '../services/local_storage_service.dart';
import '../theme/spendant_theme.dart';
import '../widgets/auth_chrome.dart';
import '../widgets/spendant_bottom_nav.dart';
import '../widgets/spendant_delete_dialog.dart';
import 'edit_profile_screen.dart';
import 'new_expense_screen.dart';

class SetGoalScreen extends StatefulWidget {
  const SetGoalScreen({super.key});

  @override
  State<SetGoalScreen> createState() => _SetGoalScreenState();
}

class _SetGoalScreenState extends State<SetGoalScreen> {
  static final NumberFormat _currencyFormat = NumberFormat('#,###', 'en_US');

  int _currentStep = -1;
  int _viewState = 0;
  bool _didLoadInitialView = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  DateTime _goalDeadline = DateTime.now().add(const Duration(days: 30));
  GoalModel? _editingGoal;
  String? _goalBudgetBlockedTitle;
  String? _goalBudgetBlockedMessage;
  bool _isSavingGoal = false;
  String _profileName = 'John Doe';
  String _profileHandle = '@johndoe';
  Uint8List? _profileAvatarBytes;
  String? _profileAvatarBase64;
  int get _currentUserId => AuthMemoryStore.currentUserIdOrGuest;

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
    final currentUser = LocalStorageService().getUserById(_currentUserId);
    final rawName = currentUser?.displayName?.trim().isNotEmpty == true
        ? currentUser!.displayName!.trim()
        : authState.username?.trim();
    final displayName = rawName == null || rawName.isEmpty
        ? 'John Doe'
        : rawName;

    if (!mounted) {
      return;
    }

    setState(() {
      _profileName = displayName;
      _profileHandle = _buildHandle(displayName);
      _profileAvatarBase64 = authState.avatarBase64;
      _profileAvatarBytes = _decodeAvatar(authState.avatarBase64);
    });
  }

  Uint8List? _decodeAvatar(String? avatarBase64) {
    if (avatarBase64 == null || avatarBase64.isEmpty) {
      return null;
    }

    try {
      return base64Decode(avatarBase64);
    } catch (_) {
      return null;
    }
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
    final updatedProfile = await Navigator.of(context).push<ProfileEditResult>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          initialName: _profileName,
          initialAvatarBase64: _profileAvatarBase64,
        ),
      ),
    );

    if (updatedProfile == null || !mounted) {
      return;
    }

    final trimmedName = updatedProfile.name.trim();
    if (trimmedName.isEmpty) {
      return;
    }

    final currentUserId = _currentUserId;
    final currentUser = LocalStorageService().getUserById(currentUserId);
    if (currentUser != null) {
      currentUser
        ..username = trimmedName
        ..displayName = trimmedName
        ..handle = _buildHandle(trimmedName)
        ..isSynced = false;
      await currentUser.save();
    }
    await AuthMemoryStore.saveProfile(
      username: trimmedName,
      avatarBase64: updatedProfile.avatarBase64,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _profileName = trimmedName;
      _profileHandle = _buildHandle(trimmedName);
      _profileAvatarBase64 = updatedProfile.avatarBase64;
      _profileAvatarBytes = _decodeAvatar(updatedProfile.avatarBase64);
    });
  }

  void _goToHome() {
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  void _startGoalSetup({GoalModel? goal}) {
    FocusScope.of(context).unfocus();

    final summary = _budgetSummary();
    if (goal == null && !summary.hasIncome) {
      _showMessage('Add an income first so we can calculate your daily budget');
      return;
    }

    if (goal == null) {
      _resetGoalForm();
    } else {
      _editingGoal = goal;
      _nameController.text = goal.name;
      _amountController.text = NumberFormat(
        '#,###',
        'en_US',
      ).format(goal.targetAmount.round());
      _goalDeadline = goal.deadline;
    }
    setState(() {
      _currentStep = 0;
    });
  }

  void _closeGoalSetup() {
    FocusScope.of(context).unfocus();
    _resetGoalForm();
    setState(() {
      _currentStep = -1;
    });
  }

  void _resetGoalForm() {
    _nameController.clear();
    _amountController.clear();
    _goalDeadline = DateTime.now().add(const Duration(days: 30));
    _editingGoal = null;
    _goalBudgetBlockedTitle = null;
    _goalBudgetBlockedMessage = null;
  }

  double? _parsedGoalAmount() {
    final amountText = _amountController.text.replaceAll(',', '').trim();
    return double.tryParse(amountText);
  }

  DailyBudgetSummary _budgetSummary() {
    return DailyBudgetService.buildSummaryForUser(_currentUserId);
  }

  GoalBudgetValidationResult? _goalValidation() {
    final amount = _parsedGoalAmount();
    if (amount == null || amount <= 0) {
      return null;
    }

    final editingGoal = _editingGoal;
    if (editingGoal == null) {
      return DailyBudgetService.validateNewGoal(
        userId: _currentUserId,
        targetAmount: amount,
        currentAmount: 0,
        deadline: _goalDeadline,
      );
    }

    final summary = _budgetSummary();
    final currentGoalDailyCommitment = DailyBudgetService.dailyGoalContribution(
      editingGoal,
    );
    final editedDailyGoalAmount =
        DailyBudgetService.projectedGoalDailyContribution(
          targetAmount: amount,
          currentAmount: editingGoal.currentAmount,
          deadline: _goalDeadline,
          isCompleted: editingGoal.currentAmount >= amount,
        );
    final remainingGoalsCommitment =
        summary.totalGoalDailyCommitment - currentGoalDailyCommitment;
    final projectedGoalDailyCommitment =
        remainingGoalsCommitment + editedDailyGoalAmount;

    return GoalBudgetValidationResult(
      hasIncome: summary.hasIncome,
      dailyGoalAmount: editedDailyGoalAmount,
      currentGoalDailyCommitment: remainingGoalsCommitment,
      projectedGoalDailyCommitment: projectedGoalDailyCommitment,
      availableInternalDailyBudget: summary.internalDailyBudget,
      goalFitsOnItsOwn:
          editedDailyGoalAmount <= summary.internalDailyBudget + 0.0001,
      goalFitsWithAllGoals:
          projectedGoalDailyCommitment <= summary.internalDailyBudget + 0.0001,
    );
  }

  String _formatCop(double amount) {
    return 'COP ${_currencyFormat.format(amount.round())}';
  }

  void _showGoalBudgetBlockedScreen(GoalBudgetValidationResult validation) {
    final title = switch (validation) {
      GoalBudgetValidationResult(:final hasIncome) when !hasIncome =>
        'No budget available for this goal',
      GoalBudgetValidationResult(:final goalFitsOnItsOwn)
          when !goalFitsOnItsOwn =>
        'This goal does not fit your current budget',
      _ => 'Your current budget cannot support this goal',
    };

    final message = switch (validation) {
      GoalBudgetValidationResult(:final hasIncome) when !hasIncome =>
        'With your current setup, this goal cannot be created because you do not have an active income feeding the daily budget yet. Go back to Goals and add income first.',
      GoalBudgetValidationResult(
        :final goalFitsOnItsOwn,
        :final dailyGoalAmount,
        :final availableInternalDailyBudget,
      )
          when !goalFitsOnItsOwn =>
        'With your current budget, this goal cannot be reached using the selected amount and deadline. It would need about ${_formatCop(dailyGoalAmount)} per day, but your internal daily budget is only ${_formatCop(availableInternalDailyBudget)}.',
      GoalBudgetValidationResult(
        :final projectedGoalDailyCommitment,
        :final currentGoalDailyCommitment,
        :final availableInternalDailyBudget,
      ) =>
        'With your current budget and the other goals you already have, this goal cannot be reached with the selected parameters. Your existing goals already reserve ${_formatCop(currentGoalDailyCommitment)} per day, and this one would push the total to ${_formatCop(projectedGoalDailyCommitment)} over an internal daily budget of ${_formatCop(availableInternalDailyBudget)}.',
    };

    setState(() {
      _goalBudgetBlockedTitle = title;
      _goalBudgetBlockedMessage = message;
      _currentStep = 4;
    });
  }

  void _returnToGoalsView() {
    FocusScope.of(context).unfocus();
    _resetGoalForm();
    setState(() {
      _currentStep = -1;
      _viewState = 1;
    });
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
          _showGoalBudgetBlockedScreen(validation);
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
        _showGoalBudgetBlockedScreen(validation);
      }
      return;
    }

    setState(() {
      _isSavingGoal = true;
    });

    GoalModel? createdGoal;
    try {
      final editingGoal = _editingGoal;
      if (editingGoal == null) {
        final goal = GoalModel()
          ..userId = _currentUserId
          ..name = _nameController.text.trim()
          ..targetAmount = amount
          ..currentAmount = 0
          ..deadline = _goalDeadline
          ..isCompleted = false
          ..createdAt = DateTime.now()
          ..isSynced = false;
        await LocalStorageService().saveGoal(goal);
        createdGoal = goal;
      } else {
        editingGoal
          ..userId = _currentUserId
          ..name = _nameController.text.trim()
          ..targetAmount = amount
          ..deadline = _goalDeadline
          ..isCompleted = editingGoal.currentAmount >= amount
          ..isSynced = false;
        await editingGoal.save();
      }
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

    setState(() {
      _isSavingGoal = false;
      _currentStep = -1;
      _viewState = 1;
    });
    if (createdGoal != null) {
      unawaited(AppNotificationService.notifyGoalCreated(createdGoal));
    }
    _resetGoalForm();
    _syncPendingDataInBackground();
  }

  void _syncPendingDataInBackground() {
    unawaited(_runPendingCloudSync());
  }

  Future<void> _runPendingCloudSync() async {
    try {
      await CloudSyncService().syncAllPendingData();
    } catch (_) {
      return;
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

  Future<bool> _showDeleteConfirmation({
    required String title,
    required String name,
  }) async {
    return showSpendAntDeleteDialog(context, title: title, name: name);
  }

  Future<void> _confirmDeleteGoal(GoalModel goal) async {
    final shouldDelete = await _showDeleteConfirmation(
      title: 'Delete goal?',
      name: goal.name,
    );
    if (!shouldDelete || !mounted) {
      return;
    }

    final deletedFromCloud = await CloudSyncService().deleteGoalRecord(goal);
    if (!mounted) {
      return;
    }

    _showMessage(
      deletedFromCloud
          ? 'Goal deleted'
          : 'Goal deleted locally. Cloud cleanup is still pending',
    );
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
              CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFFFFCCBB),
                backgroundImage: _profileAvatarBytes != null
                    ? MemoryImage(_profileAvatarBytes!)
                    : null,
                child: _profileAvatarBytes == null
                    ? const Icon(
                        Icons.person,
                        color: Color(0xFFFF9999),
                        size: 45,
                      )
                    : null,
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
              assetPath: 'web/icons/IncomeWhite.svg',
              isIncomeBtn: true,
            ),
            const SizedBox(width: 16),
            _profileActionButton(
              'Goals',
              icon: Icons.flag_outlined,
              isGoalBtn: true,
            ),
          ],
        ),
        const Spacer(),
        const Center(
          child: SizedBox(
            width: 200,
            height: 250,
            child: AntAsset('web/ant/ant_idle.svg'),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _profileActionButton(
    String label, {
    IconData? icon,
    String? assetPath,
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
      icon: assetPath != null
          ? SvgPicture.asset(assetPath, width: 20, height: 20)
          : Icon(icon, size: 20, color: Colors.white),
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

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 58, 20, 14),
          color: AppPalette.green,
          child: Row(
            children: [
              IconButton(
                onPressed: _goToHome,
                icon: const Icon(Icons.close, size: 28, color: AppPalette.ink),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Goals',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunito(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppPalette.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 48),
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
                      .where((goal) => goal.userId == _currentUserId)
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
                  for (final goal in goals)
                    _GoalTile(
                      goal: goal,
                      onDelete: () => _confirmDeleteGoal(goal),
                      onEdit: () => _startGoalSetup(goal: goal),
                    ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: canCreateGoal
                        ? _startGoalSetup
                        : () =>
                              Navigator.of(context).pushNamed(AppRoutes.budget),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: Text(
                      canCreateGoal ? 'New Goal' : 'Add Income First',
                      style: const TextStyle(
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
    );
  }

  Widget _buildGoalSetupFlow() {
    switch (_currentStep) {
      case 0:
        return _setupStepLayout(
          'What are you saving for?',
          _setupTextField(_nameController, 'e.g. A new car'),
          'web/ant/ant_presenting.svg',
        );
      case 1:
        return _setupStepLayout(
          'How much money do you want to save?',
          _setupTextField(_amountController, '\$0', isNum: true),
          'web/ant/ant_idle.svg',
        );
      case 2:
        return _setupStepLayout(
          'When is the deadline?',
          _setupDatePicker(),
          'web/ant/ant_suprised.svg',
        );
      case 3:
        return _buildStepPlan();
      case 4:
        return _buildGoalBudgetBlockedStep();
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
    final rawDaysLeft = _goalDeadline
        .difference(DateUtils.dateOnly(DateTime.now()))
        .inDays;
    final daysLeft = rawDaysLeft < 1 ? 1 : rawDaysLeft;
    final suggestedDailySaving = amount / daysLeft;
    final validation = _goalValidation();

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
            const SizedBox(height: 40),
            const SizedBox(
              height: 180,
              child: AntAsset('web/ant/ant_thumb.svg'),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _isSavingGoal
                  ? null
                  : () {
                      if (validation?.canCreateGoal == true) {
                        _finishGoalSetup();
                        return;
                      }
                      if (validation != null) {
                        _showGoalBudgetBlockedScreen(validation);
                      }
                    },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: Text(
                _isSavingGoal
                    ? (_editingGoal == null ? 'Saving...' : 'Updating...')
                    : (_editingGoal == null ? 'Alright!' : 'Update Goal'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalBudgetBlockedStep() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: _returnToGoalsView,
                icon: const Icon(Icons.close, size: 30),
              ),
            ),
            const Spacer(),
            Text(
              _goalBudgetBlockedTitle ?? 'This goal does not fit right now',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppPalette.ink,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _goalBudgetBlockedMessage ??
                  'With your current budget, this goal cannot be achieved with the parameters you selected.',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppPalette.ink,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'Try changing the target amount, extending the deadline, or increasing your available income before creating this goal again.',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.ink,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 34),
            const SizedBox(
              height: 170,
              child: AntAsset('web/ant/ant_suprised.svg'),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _returnToGoalsView,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text(
                'Back to Goals',
                style: TextStyle(color: Colors.white),
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
  const _GoalTile({
    required this.goal,
    required this.onDelete,
    required this.onEdit,
  });

  final GoalModel goal;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final progress = goal.getProgressPercent() / 100;
    final widthFactor = progress.clamp(0.0, 1.0).toDouble();
    final dailyReserve = DailyBudgetService.dailyGoalContribution(goal);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppPalette.field,
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
            backgroundColor: AppPalette.green.withValues(alpha: 0.2),
            child: const Icon(
              Icons.flag_outlined,
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
                  goal.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.ink,
                  ),
                ),
                Text(
                  'Deadline: ${DateFormat('d/M/y').format(goal.deadline)}',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Saved: COP ${NumberFormat('#,###', 'en_US').format(goal.currentAmount.round())} / ${NumberFormat('#,###', 'en_US').format(goal.targetAmount.round())}',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Daily reserve: COP ${NumberFormat('#,###', 'en_US').format(dailyReserve.round())}',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: widthFactor,
                    minHeight: 8,
                    backgroundColor: Colors.white,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppPalette.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${goal.getProgressPercent()}%',
                style: GoogleFonts.nunito(
                  fontSize: 20,
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
                      color: AppPalette.ink,
                    ),
                    tooltip: 'Delete goal',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
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

class _GoalRulesNotice extends StatelessWidget {
  const _GoalRulesNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.amber.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline, color: AppPalette.ink, size: 18),
          ),
          const SizedBox(width: 10),
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

class _EmptyGoalsCard extends StatelessWidget {
  const _EmptyGoalsCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          'No goals yet.\nTap "New Goal" to add one.',
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
