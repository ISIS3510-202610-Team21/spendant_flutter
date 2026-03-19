import 'package:flutter/material.dart';
import '../models/expense_model.dart';
import '../models/goal_model.dart';
import '../services/local_storage_service.dart';

/// Debug screen para verificar que el almacenamiento local funciona
class DebugStorageScreen extends StatefulWidget {
  const DebugStorageScreen({super.key});

  @override
  State<DebugStorageScreen> createState() => _DebugStorageScreenState();
}

class _DebugStorageScreenState extends State<DebugStorageScreen> {
  final storage = LocalStorageService();
  List<ExpenseModel> expenses = [];
  List<GoalModel> goals = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final exp = await storage.getAllExpenses();
    final gls = await storage.getAllGoals();
    setState(() {
      expenses = exp;
      goals = gls;
    });
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
      ..createdAt = DateTime.now();

    await storage.saveExpense(expense);
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gasto de prueba guardado')),
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

    await storage.saveGoal(goal);
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Meta de prueba guardada')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug: Almacenamiento Local'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // === GASTOS ===
            Card(
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
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
                        child: Text('Sin gastos aún'),
                      )
                    else
                      Column(
                        children: expenses
                            .asMap()
                            .entries
                            .map((entry) {
                              final i = entry.key;
                              final exp = entry.value;
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          exp.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          exp.isSynced ? 'Nube' : 'Local',
                                          style: TextStyle(
                                            color: exp.isSynced
                                                ? Colors.green
                                                : Colors.orange,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      'COP \$${exp.amount.toStringAsFixed(0)}',
                                    ),
                                    Text(
                                      '${exp.date.day}/${exp.date.month}/${exp.date.year} ${exp.time}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            })
                            .toList(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // === METAS ===
            Card(
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
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
                        child: Text('Sin metas aún'),
                      )
                    else
                      Column(
                        children: goals
                            .asMap()
                            .entries
                            .map((entry) {
                              final i = entry.key;
                              final goal = entry.value;
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          goal.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          goal.isSynced ? 'Nube' : 'Local',
                                          style: TextStyle(
                                            color: goal.isSynced
                                                ? Colors.green
                                                : Colors.orange,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      'Meta: COP \$${goal.targetAmount.toStringAsFixed(0)}',
                                    ),
                                    Text(
                                      'Ahorrado: COP \$${goal.currentAmount.toStringAsFixed(0)}',
                                    ),
                                    LinearProgressIndicator(
                                      value: progress / 100,
                                      minHeight: 8,
                                    ),
                                    Text(
                                      '$progress% - Deadline: ${goal.deadline.day}/${goal.deadline.month}/${goal.deadline.year}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            })
                            .toList(),
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
}
