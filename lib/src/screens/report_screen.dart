import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/financial_report.dart';
import '../services/currency_provider.dart';
import '../services/pdf_report_service.dart';
import '../theme/spendant_theme.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  FinancialReport? _report;
  bool _downloadingPdf = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is FinancialReport) _report = arg;
  }

  Future<void> _downloadPdf() async {
    final report = _report;
    if (report == null) return;
    setState(() => _downloadingPdf = true);

    final path = await PdfReportService.generate(report);

    if (!mounted) return;
    setState(() => _downloadingPdf = false);

    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not generate PDF. Try again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    await PdfReportService.openFile(path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header — X close (left), Download.svg (right)
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Spending Report',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.ink,
                  ),
                ),
                if (_report != null)
                  Text(
                    _report!.periodLabel,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.fieldHint,
                    ),
                  ),
              ],
            ),
          ),
          // Download button — top right
          _downloadingPdf
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppPalette.ink,
                    ),
                  ),
                )
              : IconButton(
                  onPressed: _report != null ? _downloadPdf : null,
                  icon: SvgPicture.asset(
                    'web/icons/Download.svg',
                    width: 22,
                    height: 22,
                  ),
                  tooltip: 'Download PDF',
                ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Body
  // ---------------------------------------------------------------------------

  Widget _buildBody() {
    final report = _report;

    if (report == null) {
      return const Center(child: CircularProgressIndicator(color: AppPalette.green));
    }

    if (report.totalSpent == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_outlined, size: 56, color: Colors.black26),
              const SizedBox(height: 16),
              Text(
                'No expenses in this period.',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTotalCard(report),
          const SizedBox(height: 24),
          _buildSectionLabel('Daily Spending'),
          const SizedBox(height: 12),
          _buildHistogram(report.dailySpends),
          const SizedBox(height: 28),
          _buildSectionLabel('Top Expenses'),
          const SizedBox(height: 12),
          ...report.topExpenses.map(_buildExpenseRow),
          const SizedBox(height: 28),
          _buildSectionLabel('Top Categories'),
          const SizedBox(height: 12),
          ...report.topCategories.asMap().entries.map(
            (e) => _buildCategoryRow(e.key, e.value, report.totalSpent),
          ),
          if (report.bqInsights.isNotEmpty || report.reportsGeneratedCount > 0) ...[
            const SizedBox(height: 28),
            _buildInsights(report),
          ],
          const SizedBox(height: 16),
          Text(
            'Generated ${DateFormat('MMM d, y · HH:mm').format(report.generatedAt)}',
            style: GoogleFonts.nunito(fontSize: 11, color: Colors.black38),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BQ Insights card
  // ---------------------------------------------------------------------------

  Widget _buildInsights(FinancialReport report) {
    final items = <String>[
      ...report.bqInsights,
      if (report.reportsGeneratedCount > 0)
        'You have generated ${report.reportsGeneratedCount} '
        '${report.reportsGeneratedCount == 1 ? 'report' : 'reports'} so far',
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppPalette.field,
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Insights',
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppPalette.ink,
            ),
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                item,
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Total card
  // ---------------------------------------------------------------------------

  Widget _buildTotalCard(FinancialReport report) {
    final iso = CurrencyProvider.instance.activeCurrency;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: const BoxDecoration(
        color: AppPalette.field,
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total spent',
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$iso ${_fmt(report.totalSpent)}',
            style: GoogleFonts.nunito(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppPalette.ink,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Histogram
  // ---------------------------------------------------------------------------

  Widget _buildHistogram(List<DailySpend> days) {
    if (days.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(child: Text('No data', style: TextStyle(color: Colors.black38))),
      );
    }
    return SizedBox(height: 140, child: _BarChart(days: days));
  }

  // ---------------------------------------------------------------------------
  // Expense row
  // ---------------------------------------------------------------------------

  Widget _buildExpenseRow(TopExpense e) {
    final iso = CurrencyProvider.instance.activeCurrency;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
          color: AppPalette.field,
          borderRadius: AppRadius.cardTile,
          border: Border(
            bottom: BorderSide(color: AppPalette.cardBorderGray, width: 2),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name,
                      style: GoogleFonts.nunito(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  Text(e.category,
                      style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54)),
                ],
              ),
            ),
            Text(
              '$iso ${_fmt(e.amount)}',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppPalette.expenseRed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Category row
  // ---------------------------------------------------------------------------

  Widget _buildCategoryRow(int index, CategoryTotal cat, double total) {
    final fraction = total > 0 ? (cat.amount / total).clamp(0.0, 1.0) : 0.0;
    final iso = CurrencyProvider.instance.activeCurrency;
    const colors = [
      AppPalette.green,
      Color(0xFF4AD3F5),
      Color(0xFFB87DE9),
      Color(0xFFFF886E),
      Color(0xFFBDDD34),
    ];
    final color = colors[index % colors.length];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(cat.label,
                    style: GoogleFonts.nunito(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              Text('$iso ${_fmt(cat.amount)}',
                  style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: AppRadius.pill,
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 7,
              backgroundColor: AppPalette.cardBorderGray,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
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
    return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)
        .replaceAll(RegExp(r'\.?0+$'), '');
  }
}

// ---------------------------------------------------------------------------
// Bar chart — CustomPainter
// ---------------------------------------------------------------------------

class _BarChart extends StatelessWidget {
  const _BarChart({required this.days});
  final List<DailySpend> days;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 140),
      painter: _BarChartPainter(days: days),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  const _BarChartPainter({required this.days});
  final List<DailySpend> days;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    const labelH = 20.0;
    const topPad = 8.0;
    final chartH = size.height - labelH - topPad;

    final maxAmt = days.map((d) => d.amount).reduce(math.max);
    if (maxAmt == 0) return;

    final barW = (size.width / days.length) * 0.6;
    final gap  = size.width / days.length;

    final barPaint = Paint()
      ..color = AppPalette.green
      ..style = PaintingStyle.fill;

    for (var i = 0; i < days.length; i++) {
      final barH = (days[i].amount / maxAmt) * chartH;
      final x    = i * gap + (gap - barW) / 2;
      final y    = topPad + chartH - barH;

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, barW, barH),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        barPaint,
      );

      // Label every Nth bar
      final step = math.max(1, (days.length / 7).ceil());
      if (i % step == 0) {
        final label = DateFormat('d').format(days[i].date);
        final tp = ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: TextAlign.center,
          fontSize: 9,
        ))
          ..pushStyle(ui.TextStyle(color: const ui.Color(0x99000000)))
          ..addText(label);
        final para = tp.build()
          ..layout(ui.ParagraphConstraints(width: barW + gap));
        canvas.drawParagraph(
          para,
          Offset(x + barW / 2 - (barW + gap) / 2, topPad + chartH + 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) => old.days != days;
}
