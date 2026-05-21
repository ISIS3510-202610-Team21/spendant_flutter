import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/currency_provider.dart';
import '../theme/spendant_theme.dart';

// ---------------------------------------------------------------------------
// Data — the 14 supported currencies
// ---------------------------------------------------------------------------

class _CurrencyInfo {
  const _CurrencyInfo({required this.iso, required this.name});
  final String iso;
  final String name;
}

/// Pastel accent colors for the 14 list cards.
/// 0xFF297DE7 is intentionally excluded — it is reserved for the selected
/// (top sticky) card.  Yellow is included here so it cycles through the list.
const List<Color> _kCurrencyColors = [
  Color(0xFF78E4B0), // mint green
  Color(0xFFB87DE9), // purple
  Color(0xFF4AD3F5), // cyan
  Color(0xFFBDDD34), // lime
  Color(0xFF9A1737), // dark red
  Color(0xFFFF886E), // salmon
  Color(0xFFFCC34D), // yellow 
  Color(0xFFA1BF9D), // sage green
  Color(0xFF5B204E), // dark purple
  Color(0xFFD1A039), // gold
];

const List<_CurrencyInfo> _kSupportedCurrencies = [
  _CurrencyInfo(iso: 'COP', name: 'Colombian Peso'),
  _CurrencyInfo(iso: 'USD', name: 'US Dollar'),
  _CurrencyInfo(iso: 'EUR', name: 'Euro'),
  _CurrencyInfo(iso: 'GBP', name: 'British Pound'),
  _CurrencyInfo(iso: 'JPY', name: 'Japanese Yen'),
  _CurrencyInfo(iso: 'CAD', name: 'Canadian Dollar'),
  _CurrencyInfo(iso: 'AUD', name: 'Australian Dollar'),
  _CurrencyInfo(iso: 'MXN', name: 'Mexican Peso'),
  _CurrencyInfo(iso: 'BRL', name: 'Brazilian Real'),
  _CurrencyInfo(iso: 'CLP', name: 'Chilean Peso'),
  _CurrencyInfo(iso: 'PEN', name: 'Peruvian Sol'),
  _CurrencyInfo(iso: 'ARS', name: 'Argentine Peso'),
  _CurrencyInfo(iso: 'CHF', name: 'Swiss Franc'),
  _CurrencyInfo(iso: 'CNY', name: 'Chinese Yuan'),
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Full-screen currency selector.
///
/// On confirm (✓), persists the selected currency into [CurrencyProvider] and
/// pops.  On cancel (✗), pops without saving.
class CurrencyConverterScreen extends StatefulWidget {
  const CurrencyConverterScreen({super.key});

  @override
  State<CurrencyConverterScreen> createState() =>
      _CurrencyConverterScreenState();
}

class _CurrencyConverterScreenState extends State<CurrencyConverterScreen> {
  /// ISO code of the currency currently pinned to the top sticky card.
  late String _selectedIso;

  @override
  void initState() {
    super.initState();
    // Initialise with whatever is already active globally.
    _selectedIso = CurrencyProvider.instance.activeCurrency;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Rate from COP to [iso], sourced from the in-memory cache.
  double _rateFor(String iso) => CurrencyProvider.instance.rateFor(iso);

  /// Equivalence label displayed on the right side of each list card.
  ///
  /// Formula: Rate_COP→listCurrency / Rate_COP→selectedCurrency
  /// This gives "1 [listCurrency] = X [selectedCurrency]".
  String _equivalenceLabel(String listIso) {
    final rateList = _rateFor(listIso);
    final rateSel = _rateFor(_selectedIso);
    if (rateSel == 0 || rateList == 0) {
      return '—';
    }
    // rate[X] = "1 COP expressed in X".
    // To get "1 listIso = X selectedIso":
    //   1 listIso = (1 / rateList) COP = (rateSel / rateList) selectedIso
    final crossRate = rateSel / rateList;
    // Display whole numbers for COP/JPY/CLP, two decimals otherwise.
    const wholeNumber = {'COP', 'JPY', 'CLP', 'ARS'};
    final formatted = wholeNumber.contains(_selectedIso)
        ? crossRate.round().toString()
        : crossRate.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return '1 $listIso = $formatted $_selectedIso';
  }

  Color _accentColorFor(int index) =>
      _kCurrencyColors[index % _kCurrencyColors.length];

  Color _bgColorFor(int index) {
    final accent = _accentColorFor(index);
    return Color.lerp(accent, Colors.white, 0.76)!;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _selectFromList(_CurrencyInfo info) {
    setState(() => _selectedIso = info.iso);
  }

  void _confirm() {
    final rate = _rateFor(_selectedIso);
    CurrencyProvider.instance.setActiveCurrency(_selectedIso, rate);
    Navigator.of(context).pop();
  }

  void _cancel() => Navigator.of(context).pop();

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Find the selected entry to show in the sticky top card.
    final selectedInfo = _kSupportedCurrencies.firstWhere(
      (c) => c.iso == _selectedIso,
      orElse: () => _kSupportedCurrencies.first,
    );

    // Remaining currencies for the scrollable list (all 14 — user can pick any).
    final listCurrencies = _kSupportedCurrencies
        .where((c) => c.iso != _selectedIso)
        .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: Column(
                children: [
                  _buildSelectedCard(selectedInfo),
                  Expanded(child: _buildCurrencyList(listCurrencies)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AppBar
  // ---------------------------------------------------------------------------

  Widget _buildAppBar() {
    return Container(
      color: AppPalette.green,
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.paddingOf(context).top + 12,
        8,
        12,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _cancel,
            icon: const Icon(Icons.close, color: AppPalette.ink, size: 22),
            tooltip: 'Cancel',
          ),
          Expanded(
            child: Text(
              'Currency Converter',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppPalette.ink,
              ),
            ),
          ),
          IconButton(
            onPressed: _confirm,
            icon: const Icon(Icons.check, color: AppPalette.ink, size: 22),
            tooltip: 'Confirm',
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Selected (top sticky) card
  // ---------------------------------------------------------------------------

  static const _kSelectedAccent = Color(0xFF297DE7);
  static final _kSelectedBg = Color.lerp(
    _kSelectedAccent,
    Colors.white,
    0.82,
  )!;

  Widget _buildSelectedCard(_CurrencyInfo info) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            decoration: BoxDecoration(
              color: _kSelectedBg,
              borderRadius: BorderRadius.zero,
              border: Border.all(
                color: _kSelectedAccent.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                _CurrencyBadge(iso: info.iso, color: _kSelectedAccent),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    info.name,
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.ink,
                    ),
                  ),
                ),
                Text(
                  '1 ${info.iso} = 1 ${info.iso}',
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.fieldHint,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Divider(
          height: 4,
          thickness: 4,
          color: AppPalette.cardBorderGray,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Scrollable list
  // ---------------------------------------------------------------------------

  Widget _buildCurrencyList(List<_CurrencyInfo> currencies) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      itemCount: currencies.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final info = currencies[index];
        // Use a stable colour index based on the global list position so
        // colours don't shift when the list reorders after a selection.
        final globalIndex = _kSupportedCurrencies.indexWhere(
          (c) => c.iso == info.iso,
        );
        return _buildListCard(info, globalIndex, index);
      },
    );
  }

  Widget _buildListCard(_CurrencyInfo info, int colorIndex, int listIndex) {
    final bg = _bgColorFor(colorIndex);
    final accent = _accentColorFor(colorIndex);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      child: GestureDetector(
        onTap: () => _selectFromList(info),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.zero,
            border: const Border(
              bottom: BorderSide(color: AppPalette.cardBorderGray, width: 2),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _CurrencyBadge(iso: info.iso, color: accent),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  info.name,
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.ink,
                  ),
                ),
              ),
              Text(
                _equivalenceLabel(info.iso),
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.fieldHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable badge widget — circular with ISO abbreviation
// ---------------------------------------------------------------------------

class _CurrencyBadge extends StatelessWidget {
  const _CurrencyBadge({required this.iso, required this.color});

  final String iso;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        iso.length > 3 ? iso.substring(0, 3) : iso,
        style: GoogleFonts.nunito(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}
