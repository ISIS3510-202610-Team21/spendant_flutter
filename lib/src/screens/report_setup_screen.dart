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
    final recent = await ReportCacheService.listRecent(userId);

    if (!mounted) return;
    setState(() {
      _firstExpenseDate = first;
      // Clamp startDate to first expense
      if (first != null && _startDate.isBefore(first)) {
        _startDate = first;
      }
      _recentReports = recent;
    });
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
          minDate: min,
          maxDate: _endDate,  // start cannot exceed current end
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _startDate = result;
        // If start overtook end, move end forward
        if (_startDate.isAfter(_endDate)) {
          _endDate = _startDate;
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final result = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) => DateSelectionScreen(
          initialDate: _endDate,
          minDate: _startDate,   // end cannot precede start
          maxDate: _today,       // end cannot exceed today
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _endDate = result);
    }
  }

  // ---------------------------------------------------------------------------
  // Generate
  // ---------------------------------------------------------------------------

  Future<void> _generate() async {
    setState(() => _generating = true);
    final report = await ReportWorker.generate(
      startDate: _startDate,
      endDate:   _endDate,
    );
    if (!mounted) return;
    setState(() => _generating = false);

    if (report != null) {
      await Navigator.of(context).pushNamed(
        AppRoutes.report,
        arguments: report,
      );
      // Refresh recent list after returning
      _loadConstraintsAndRecent();
    }
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
                    if (_recentReports.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _buildSectionLabel(
                        _recentReports.length == 1
                            ? 'Last report (cached)'
                            : 'Recent reports (cached)',
                      ),
                      const SizedBox(height: 10),
                      ..._recentReports.map(_buildRecentCard),
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
