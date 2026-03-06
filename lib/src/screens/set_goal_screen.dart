import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para los formatters
import 'package:google_fonts/google_fonts.dart';
import '../../app.dart';
import '../theme/spendant_theme.dart';
import '../widgets/auth_chrome.dart';

class SetGoalScreen extends StatefulWidget {
  const SetGoalScreen({super.key});

  @override
  State<SetGoalScreen> createState() => _SetGoalScreenState();
}

class _SetGoalScreenState extends State<SetGoalScreen> {
  int _currentStep = -1;
  int _viewState = 0;

  // Controllers para que no se borre el texto al cambiar de pantalla
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  DateTime _goalDeadline = DateTime.now().add(const Duration(days: 30));

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
          _buildBottomNav(),
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
          padding: const EdgeInsets.only(top: 80, bottom: 40),
          decoration: const BoxDecoration(
            color: AppPalette.green,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
          ),
          child: Column(
            children: [
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 15,
            runSpacing: 15,
            alignment: WrapAlignment.center,
            children: [
              _profileActionButton('Income', Icons.attach_money),
              _profileActionButton('Goals', Icons.flag, isGoalBtn: true),
              _profileActionButton('Set Bank Account', Icons.account_balance),
            ],
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))]
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
        final d = await showDatePicker(
          context: context,
          initialDate: _goalDeadline,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        if (d != null) setState(() => _goalDeadline = d);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          "${_goalDeadline.day}/${_goalDeadline.month}/${_goalDeadline.year}",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 75,
      color: AppPalette.green,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navIcon(Icons.person, 0),
          _navIcon(Icons.home, -1),
          IconButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.newExpense),
            icon: const Icon(Icons.add_circle, color: Colors.black, size: 50),
          ),
          _navIcon(Icons.flag, 1),
          _navIcon(Icons.grid_view, -1),
        ],
      ),
    );
  }

  Widget _navIcon(IconData icon, int viewIndex) {
    return IconButton(
      onPressed: () {
        if (viewIndex != -1) setState(() => _viewState = viewIndex);
      },
      icon: Icon(icon, color: Colors.black, size: 28),
    );
  }
}
