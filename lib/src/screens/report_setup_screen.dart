import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app.dart';
import '../models/financial_report.dart';
import '../services/auth_memory_store.dart';
import '../services/report_cache_service.dart';
import '../services/report_worker.dart';
import '../theme/spendant_theme.dart';
import 'new_expense_screen.dart';

class ReportSetupScreen extends StatefulWidget {
  const ReportSetupScreen({super.key});

  @override
  State<ReportSetupScreen> createState() => _ReportSetupScreenState();
}

class _ReportSetupScreenState extends State<ReportSetupScreen> {
  late DateTime _startDate;
  late DateTime _endDate;
  final DateTime _today = DateUtils.dateOnly(DateTime.now());

  DateTime? _firstExpenseDate;
  List<FinancialReport> _recentReports = [];
  bool _generating = false;
  FinancialReport? _cachedForSelection; // cached report matching current dates

  @override
  void initState() {
    super.initState();
    _endDate   = _today;
    _startDate = _today.subtract(const Duration(days: 29));
    _loadConstraintsAndRecent();
  }

  Future<void> _loadConstraintsAndRecent() async {
    final userId = AuthMemoryStore.currentUserIdOrGuest;
    final first  = ReportWorker.firstExpenseDate(userId);

    // Compute the effective startDate AFTER applying the first-expense clamp,
    // so the cache lookup uses the same dates the user will actually see.
    final effectiveStart = (first != null && _startDate.isBefore(first))
        ? first
        : _startDate;

    final recent = await ReportCacheService.listRecent(userId);
    final cached = await ReportCacheService.get(userId, effectiveStart, _endDate);

    if (!mounted) return;
    setState(() {
      _firstExpenseDate = first;
      _startDate        = effectiveStart;
      _recentReports      = recent;
      _cachedForSelection = cached;
    });
  }

  Future<void> _checkCacheForSelection() async {
    final userId = AuthMemoryStore.currentUserIdOrGuest;
    final cached = await ReportCacheService.get(userId, _startDate, _endDate);
    if (mounted) setState(() => _cachedForSelection = cached);
  }

  // ---------------------------------------------------------------------------
  // Date pickers
  // ---------------------------------------------------------------------------

  Future<void> _pickStartDate() async {
    final min = _firstExpenseDate ?? DateTime(2020);
    final result = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) => DateSelectionScreen(
          initialDate: _startDate,
          title: 'Select period',
          minDate: min,
          maxDate: _endDate,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _startDate = result;
        if (_startDate.isAfter(_endDate)) _endDate = _startDate;
        _cachedForSelection = null; // dates changed, invalidate
      });
      _checkCacheForSelection();
    }
  }

  Future<void> _pickEndDate() async {
    final result = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) => DateSelectionScreen(
          initialDate: _endDate,
          title: 'Select period',
          minDate: _startDate,
          maxDate: _today,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _endDate            = result;
        _cachedForSelection = null;
      });
      _checkCacheForSelection();
    }
  }

  // ---------------------------------------------------------------------------
  // Generate
  // ---------------------------------------------------------------------------

  Future<void> _generate() async {
    setState(() => _generating = true);
    FinancialReport? report;
    Object? generateError;
    try {
      report = await ReportWorker.generate(
        startDate: _startDate,
        endDate:   _endDate,
      );
    } catch (e, st) {
      generateError = e;
      debugPrint('ReportWorker.generate failed: $e\n$st');
    } finally {
      if (mounted) setState(() => _generating = false);
    }

    if (!mounted) return;

    if (report == null) {
      await _showGenerateErrorDialog(generateError);
      return;
    }

    // Show cached-report button immediately (same dates = this IS the cache)
    setState(() => _cachedForSelection = report);
    if (mounted) {
      await Navigator.of(context).pushNamed(AppRoutes.report, arguments: report);
      _loadConstraintsAndRecent();
    }
  }

  Future<void> _showGenerateErrorDialog(Object? error) async {
    final bool hasExpenses = ReportWorker.firstExpenseDate(
          AuthMemoryStore.currentUserIdOrGuest,
        ) !=
        null;

    final String title;
    final String body;

    if (!hasExpenses) {
      title = 'No expenses yet';
      body =
          'Add your first expense before generating a report. '
          'Once you have expenses, select a date range and try again.';
    } else {
      title = 'Couldn\'t generate report';
      body =
          'Something went wrong while building the report. '
          'Try a different date range, or try again in a moment.';
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: GoogleFonts.nunito(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppPalette.ink,
          ),
        ),
        content: Text(
          body,
          style: GoogleFonts.nunito(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.black54,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(
              foregroundColor: AppPalette.green,
            ),
            child: Text(
              'OK',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  void _openReport(FinancialReport report) {
    Navigator.of(context).pushNamed(AppRoutes.report, arguments: report);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionLabel('Select period'),
                    const SizedBox(height: 12),
                    _buildDateRow(
                      label: 'Start',
                      date: _startDate,
                      onTap: _pickStartDate,
                    ),
                    const SizedBox(height: 10),
                    _buildDateRow(
                      label: 'End',
                      date: _endDate,
                      onTap: _pickEndDate,
                    ),
                    // "Ver este informe" — shows when current selection is cached
                    if (_cachedForSelection != null) ...[
                      const SizedBox(height: 20),
                      _buildViewCachedButton(_cachedForSelection!),
                    ],
                    // Other recent reports for different date ranges
                    if (_recentReports
                        .where((r) => r.periodKey != _cachedForSelection?.periodKey)
                        .isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildSectionLabel('Other recent reports'),
                      const SizedBox(height: 10),
                      ..._recentReports
                          .where((r) => r.periodKey != _cachedForSelection?.periodKey)
                          .map(_buildRecentCard),
                    ],
                    const SizedBox(height: 28),
                    _buildGenerateButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      color: AppPalette.green,
      padding: EdgeInsets.fromLTRB(
        8, MediaQuery.paddingOf(context).top + 12, 8, 12,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: AppPalette.ink, size: 22),
          ),
          Expanded(
            child: Text(
              'Spending Report',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppPalette.ink,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Date row
  // ---------------------------------------------------------------------------

  Widget _buildDateRow({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: AppPalette.field,
          borderRadius: AppRadius.card,
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 18, color: AppPalette.fieldHint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.fieldHint,
                    ),
                  ),
                  Text(
                    DateFormat('EEE, MMM d yyyy').format(date),
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.ink,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppPalette.fieldHint),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Recent report card
  // ---------------------------------------------------------------------------

  // "Ver este informe" — prominent button when cached report matches current dates
  Widget _buildViewCachedButton(FinancialReport report) {
    return GestureDetector(
      onTap: () => _openReport(report),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppPalette.green.withValues(alpha: 0.10),
          borderRadius: AppRadius.card,
          border: Border.all(color: AppPalette.green, width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: AppPalette.green, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'View this report',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.ink,
                    ),
                  ),
                  Text(
                    'Generated at ${DateFormat('HH:mm').format(report.generatedAt)} · tap to open',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.fieldHint,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppPalette.green),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentCard(FinancialReport report) {
    final iso = report.totalSpent == 0 ? '' : '  ·  ';
    return GestureDetector(
      onTap: () => _openReport(report),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppPalette.field,
          borderRadius: AppRadius.card,
          border: Border.all(
            color: AppPalette.green.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppPalette.green,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SvgPicture.asset(
                  'web/icons/PDF.svg',
                  width: 18,
                  height: 18,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.periodLabel,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${DateFormat('HH:mm').format(report.generatedAt)}$iso'
                    '${report.totalSpent > 0 ? _fmt(report.totalSpent) : 'No data'}',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.fieldHint,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppPalette.fieldHint),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Generate button
  // ---------------------------------------------------------------------------

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _generating ? null : _generate,
        icon: _generating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : SvgPicture.asset(
                'web/icons/PDF.svg',
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
        label: Text(
          _generating ? 'Generating…' : 'Generate Report',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.ink,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) => Text(
    text,
    style: GoogleFonts.nunito(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: AppPalette.ink,
    ),
  );

  static String _fmt(double v) {
    if (v >= 1000) return NumberFormat('#,###', 'en_US').format(v.round());
    return v.toStringAsFixed(0);
  }
}
