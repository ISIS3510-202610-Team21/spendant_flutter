import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para los formatters
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'new_expense_screen.dart';
import '../theme/spendant_theme.dart';
import '../widgets/auth_chrome.dart';
import '../widgets/spendant_bottom_nav.dart';

class SetGoalScreen extends StatefulWidget {
  const SetGoalScreen({super.key});

  @override
  State<SetGoalScreen> createState() => _SetGoalScreenState();
}

class _SetGoalScreenState extends State<SetGoalScreen> {
  int _currentStep = -1;
  int _viewState = 0;
  bool _didLoadInitialView = false;

  // Controllers para que no se borre el texto al cambiar de pantalla
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  DateTime _goalDeadline = DateTime.now().add(const Duration(days: 30));

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

  void _closeGoalSetup() {
    setState(() => _currentStep = -1);
  }

  @override
  Widget build(BuildContext context) {
    // SECCIÓN AMARILLA: SET GOAL
    if (_currentStep >= 0) {
      return Scaffold(
        backgroundColor: AppPalette.amber,
        body: _buildGoalSetupFlow(),
      );
    }

    // VISTA PRINCIPAL (PROFILE / GOALS)
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

  // --- ÁREA DE PROFILE ---
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
                    onPressed: () {},
                    icon: const Icon(Icons.edit_outlined, color: AppPalette.ink),
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
                'Juliana Rojas',
                style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '@jujuli',
                style: GoogleFonts.nunito(fontSize: 14, color: Colors.black54),
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _profileActionButton('Income', Icons.attach_money),
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
        // Hormiga Centrada
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
  }) {
    return ElevatedButton.icon(
      onPressed: () {
        if (isGoalBtn) setState(() => _viewState = 1);
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

  // --- ÁREA DE GOALS ---
  Widget _buildGoalsView() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
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
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _buildGoalTile("FEP 2026", "50%", "04/03/2026", 0.5),
                _buildGoalTile("New Laptop", "15%", "15/12/2026", 0.15),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () => setState(() => _currentStep = 0),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text(
                    'New Goal',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalTile(
    String title,
    String percent,
    String date,
    double progress,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      height: 75,
      child: Stack(
        children: [
          // Fondo Gris Ovalado
          Container(
            decoration: BoxDecoration(
              color: AppPalette.gray,
              borderRadius: BorderRadius.circular(25),
            ),
          ),
          // Barra de Progreso Interna (Llena el fondo según el porcentaje)
          FractionallySizedBox(
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                color: AppPalette.green.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(25),
              ),
            ),
          ),
          // Contenido de la Meta
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Deadline: $date',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
                Text(
                  percent,
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

  // --- FLUJO DE SETUP (AMARILLO) ---
  Widget _buildGoalSetupFlow() {
    switch (_currentStep) {
      case 0:
        return _setupStepLayout(
          "What are you saving for?",
          _setupTextField(_nameController, "e.g. A new car"),
          'web/ant/Presenting.svg',
        );
      case 1:
        return _setupStepLayout(
          "How much money do you want to save?",
          _setupTextField(_amountController, "\$0.00", isNum: true),
          'web/ant/Standing.svg',
        );
      case 2:
        return _setupStepLayout(
          "When is the deadline?",
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
        padding: const EdgeInsets.all(32.0),
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
              onPressed: () => setState(() => _currentStep++),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text(
                "Continue",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepPlan() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
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
              'To save \$${_amountController.text} for ${_nameController.text}, let\'s start today.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            const SizedBox(height: 180, child: AntAsset('web/ant/Ok.svg')),
            const Spacer(),
            ElevatedButton(
              onPressed: _closeGoalSetup,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text(
                "Alright!",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS AUXILIARES ---
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
      inputFormatters: isNum
          ? const [_GoalAmountFormatter()]
          : [],
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

    final formatted = NumberFormat('#,###', 'en_US').format(
      int.parse(digitsOnly),
    );

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
