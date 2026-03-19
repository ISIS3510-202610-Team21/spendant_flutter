import 'package:flutter/material.dart';

import '../models/expense_model.dart';
import '../models/goal_model.dart';
import '../services/cloud_sync_service.dart';
import '../services/local_storage_service.dart';

/// Debug screen para verificar almacenamiento local y sincronizacion con nube.
class DebugStorageScreen extends StatefulWidget {
  const DebugStorageScreen({super.key});

  @override
  State<DebugStorageScreen> createState() => _DebugStorageScreenState();
}

class _DebugStorageScreenState extends State<DebugStorageScreen> {
  final LocalStorageService _storage = LocalStorageService();
  final CloudSyncService _cloudSyncService = CloudSyncService();

  List<ExpenseModel> expenses = <ExpenseModel>[];
  List<GoalModel> goals = <GoalModel>[];
  CloudVerificationSummary? _verification;
  String? _cloudMessage;
  bool _isSyncing = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final exp = await _storage.getAllExpenses();
    final gls = await _storage.getAllGoals();

    if (!mounted) {
      return;
    }

    setState(() {
      expenses = exp;
      goals = gls;
    });
  }

  Future<void> _refreshAndVerify({bool showMessage = false}) async {
    await _refresh();
    if (!CloudSyncService.isSupportedPlatform) {
      return;
    }
    await _verifyCloudState(showMessage: showMessage);
  }

  Future<void> _addTestExpense() async {
    final expense = ExpenseModel()
      ..userId = 1
      ..name = 'Test Gasto ${DateTime.now().millisecond}'
      ..amount = 50000
      ..date = DateTime.now()
      ..time = '14:30'
      ..source = 'MANUAL'
      ..isPendingCategory = false
      ..isRecurring = false
      ..isSynced = false
      ..createdAt = DateTime.now()
      ..primaryCategory = 'Other'
      ..detailLabels = <String>['Debug'];

    await _storage.saveExpense(expense);
    await _refresh();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gasto de prueba guardado localmente')),
    );
  }

  Future<void> _addTestGoal() async {
    final goal = GoalModel()
      ..userId = 1
      ..name = 'Meta de prueba'
      ..targetAmount = 500000
      ..currentAmount = 0.0
      ..deadline = DateTime.now().add(const Duration(days: 30))
      ..isCompleted = false
      ..createdAt = DateTime.now()
      ..isSynced = false;

    await _storage.saveGoal(goal);
    await _refresh();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Meta de prueba guardada localmente')),
    );
  }

  Future<void> _syncPendingData() async {
    if (!CloudSyncService.isSupportedPlatform) {
      _showMessage(
        'La sincronizacion en nube se prueba desde Android, iOS, macOS, Windows o Web.',
      );
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      final summary = await _cloudSyncService.syncAllPendingData();
      await _refresh();
      final verification = await _cloudSyncService.verifyCloudState();

      if (!mounted) {
        return;
      }

      final message =
          'Subidos ${summary.uploadedTotal} registros. '
          'Fallos: ${summary.failures}. '
          'Pendientes: ${verification.pendingTotal}.';

      setState(() {
        _verification = verification;
        _cloudMessage = message;
      });
      _showMessage(message);
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = 'La sincronizacion fallo: $error';
      setState(() {
        _cloudMessage = message;
      });
      _showMessage(message);
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _verifyCloudState({bool showMessage = true}) async {
    if (!CloudSyncService.isSupportedPlatform) {
      return;
    }

    setState(() {
      _isVerifying = true;
    });

    try {
      final verification = await _cloudSyncService.verifyCloudState();

      if (!mounted) {
        return;
      }

      final message =
          'Nube: ${verification.remoteTotal} docs. '
          'Pendientes locales: ${verification.pendingTotal}. '
          'Faltantes remotos: ${verification.missingTotal}.';

      setState(() {
        _verification = verification;
        _cloudMessage = message;
      });

      if (showMessage) {
        _showMessage(message);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = 'No se pudo verificar Firestore: $error';
      setState(() {
        _cloudMessage = message;
      });

      if (showMessage) {
        _showMessage(message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final pendingExpenses = expenses
        .where((expense) => !expense.isSynced)
        .length;
    final pendingGoals = goals.where((goal) => !goal.isSynced).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug: Local + Nube'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined),
            onPressed: _isSyncing ? null : _syncPendingData,
          ),
          IconButton(
            icon: const Icon(Icons.verified_outlined),
            onPressed: _isVerifying ? null : _verifyCloudState,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _refreshAndVerify(showMessage: false),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCloudCard(),
            const SizedBox(height: 20),
            _buildLocalSummaryCard(
              pendingExpenses: pendingExpenses,
              pendingGoals: pendingGoals,
            ),
            const SizedBox(height: 20),
            _buildExpensesCard(),
            const SizedBox(height: 20),
            _buildGoalsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudCard() {
    final verification = _verification;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SINCRONIZACION EN NUBE',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (!CloudSyncService.isSupportedPlatform)
              const Text(
                'Esta build no soporta Firestore. Prueben la sync en Android, iOS, macOS, Windows o Web.',
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isSyncing ? null : _syncPendingData,
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(
                      _isSyncing ? 'Sincronizando...' : 'Sincronizar',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isVerifying ? null : _verifyCloudState,
                    icon: _isVerifying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_outlined),
                    label: Text(_isVerifying ? 'Verificando...' : 'Verificar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_cloudMessage != null)
                Text(
                  _cloudMessage!,
                  style: const TextStyle(color: Colors.black87),
                ),
              if (verification != null) ...[
                const SizedBox(height: 12),
                _buildStatusLine(
                  'Remotos',
                  '${verification.remoteTotal} documentos',
                ),
                _buildStatusLine(
                  'Pendientes locales',
                  '${verification.pendingTotal} registros',
                ),
                _buildStatusLine(
                  'Faltantes remotos',
                  '${verification.missingTotal} registros',
                  valueColor: verification.missingTotal == 0
                      ? Colors.green
                      : Colors.red,
                ),
                const Divider(height: 24),
                _buildStatusLine(
                  'Expenses',
                  'nube ${verification.remoteExpenses} | pendientes ${verification.pendingExpenses}',
                ),
                _buildStatusLine(
                  'Goals',
                  'nube ${verification.remoteGoals} | pendientes ${verification.pendingGoals}',
                ),
                _buildStatusLine(
                  'Incomes',
                  'nube ${verification.remoteIncomes} | pendientes ${verification.pendingIncomes}',
                ),
                _buildStatusLine(
                  'Labels',
                  'nube ${verification.remoteLabels} | pendientes ${verification.pendingLabels}',
                ),
                _buildStatusLine(
                  'Users',
                  'nube ${verification.remoteUsers} | pendientes ${verification.pendingUsers}',
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocalSummaryCard({
    required int pendingExpenses,
    required int pendingGoals,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RESUMEN LOCAL',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildStatusLine('Gastos guardados', '${expenses.length}'),
            _buildStatusLine('Metas guardadas', '${goals.length}'),
            _buildStatusLine('Gastos pendientes', '$pendingExpenses'),
            _buildStatusLine('Metas pendientes', '$pendingGoals'),
          ],
        ),
      ),
    );
  }

  Widget _buildExpensesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'GASTOS GUARDADOS',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                ElevatedButton(
                  onPressed: _addTestExpense,
                  child: const Text('Agregar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (expenses.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Sin gastos aun'),
              )
            else
              Column(
                children: expenses
                    .map(_buildExpenseTile)
                    .toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'METAS GUARDADAS',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                ElevatedButton(
                  onPressed: _addTestGoal,
                  child: const Text('Agregar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (goals.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Sin metas aun'),
              )
            else
              Column(
                children: goals.map(_buildGoalTile).toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseTile(ExpenseModel expense) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  expense.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                expense.isSynced ? 'Nube' : 'Local',
                style: TextStyle(
                  color: expense.isSynced ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('COP \$${expense.amount.toStringAsFixed(0)}'),
          Text(
            'serverId: ${expense.serverId ?? 'sin asignar'}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          Text(
            '${expense.date.day}/${expense.date.month}/${expense.date.year} ${expense.time}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalTile(GoalModel goal) {
    final progress = goal.getProgressPercent();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  goal.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                goal.isSynced ? 'Nube' : 'Local',
                style: TextStyle(
                  color: goal.isSynced ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Meta: COP \$${goal.targetAmount.toStringAsFixed(0)}'),
          Text('Ahorrado: COP \$${goal.currentAmount.toStringAsFixed(0)}'),
          Text(
            'serverId: ${goal.serverId ?? 'sin asignar'}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress / 100, minHeight: 8),
          const SizedBox(height: 6),
          Text(
            '$progress% - Deadline: ${goal.deadline.day}/${goal.deadline.month}/${goal.deadline.year}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusLine(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
