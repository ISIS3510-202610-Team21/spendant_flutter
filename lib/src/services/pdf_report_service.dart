import 'dart:io';
import 'dart:ui' show Rect, Offset;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/financial_report.dart';
import '../services/currency_provider.dart';

/// Generates a branded PDF from a [FinancialReport] and saves it to
/// the device's Downloads folder.  Returns the saved file path on success.
abstract final class PdfReportService {
  static final _green  = PdfColor(68, 198, 105);
  static final _ink    = PdfColor(0, 0, 0);
  static final _gray   = PdfColor(94, 94, 94);
  static final _field  = PdfColor(224, 255, 233);
  static final _red    = PdfColor(240, 76, 76);
  static final _white  = PdfColor(255, 255, 255);

  static Future<String?> generate(FinancialReport report) async {
    if (kIsWeb) return null;
    try {
      final bytes = _buildPdf(report);
      return await _save(report, bytes);
    } catch (error) {
      debugPrint('PdfReportService.generate failed: $error');
      return null;
    }
  }

  // ---------------------------------------------------------------------------

  static Uint8List _buildPdf(FinancialReport report) {
    final doc  = PdfDocument();
    final page = doc.pages.add();
    final g    = page.graphics;
    final w    = page.getClientSize().width;
    final h    = page.getClientSize().height;

    final boldFont    = PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold);
    final titleFont   = PdfStandardFont(PdfFontFamily.helvetica, 22, style: PdfFontStyle.bold);
    final appFont     = PdfStandardFont(PdfFontFamily.helvetica, 26, style: PdfFontStyle.bold);
    final labelFont   = PdfStandardFont(PdfFontFamily.helvetica, 10);
    final smallFont   = PdfStandardFont(PdfFontFamily.helvetica, 9);
    final secFont     = PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold);
    final subFont     = PdfStandardFont(PdfFontFamily.helvetica, 11);

    double y = 0;

    // ── Green header ─────────────────────────────────────────────────────────
    g.drawRectangle(
      brush: PdfSolidBrush(_green),
      bounds: Rect.fromLTWH(0, 0, w, 72),
    );
    g.drawString('SpendAnt', appFont,
        brush: PdfSolidBrush(_white),
        bounds: Rect.fromLTWH(16, 12, 180, 32));
    g.drawString('Financial Report', subFont,
        brush: PdfSolidBrush(_white),
        bounds: Rect.fromLTWH(16, 46, 180, 18));
    g.drawString(report.periodLabel, boldFont,
        brush: PdfSolidBrush(_white),
        bounds: Rect.fromLTWH(w - 200, 26, 190, 20),
        format: PdfStringFormat(alignment: PdfTextAlignment.right));
    y = 88;

    // ── Total card ────────────────────────────────────────────────────────────
    final iso = CurrencyProvider.instance.activeCurrency;
    g.drawRectangle(
      brush: PdfSolidBrush(_field),
      bounds: Rect.fromLTWH(0, y, w, 58),
    );
    g.drawString('Total Spent', labelFont,
        brush: PdfSolidBrush(_gray), bounds: Rect.fromLTWH(16, y + 8, 200, 16));
    g.drawString('$iso ${_fmt(report.totalSpent)}', titleFont,
        brush: PdfSolidBrush(_ink), bounds: Rect.fromLTWH(16, y + 24, w - 32, 28));
    y += 72;

    // ── Histogram ─────────────────────────────────────────────────────────────
    if (report.dailySpends.isNotEmpty) {
      g.drawString('Daily Spending', secFont,
          brush: PdfSolidBrush(_ink), bounds: Rect.fromLTWH(0, y, w, 18));
      y += 22;
      _drawHistogram(g, report.dailySpends, Rect.fromLTWH(0, y, w, 70));
      y += 82;
    }

    // ── Top expenses ──────────────────────────────────────────────────────────
    if (report.topExpenses.isNotEmpty) {
      g.drawString('Top Expenses', secFont,
          brush: PdfSolidBrush(_ink), bounds: Rect.fromLTWH(0, y, w, 18));
      y += 22;
      for (final e in report.topExpenses) {
        g.drawRectangle(
            brush: PdfSolidBrush(_field),
            bounds: Rect.fromLTWH(0, y, w, 30));
        g.drawString(e.name, boldFont,
            brush: PdfSolidBrush(_ink),
            bounds: Rect.fromLTWH(8, y + 4, w * 0.6, 14));
        g.drawString(e.category, smallFont,
            brush: PdfSolidBrush(_gray),
            bounds: Rect.fromLTWH(8, y + 18, w * 0.5, 10));
        g.drawString('$iso ${_fmt(e.amount)}', boldFont,
            brush: PdfSolidBrush(_red),
            bounds: Rect.fromLTWH(w * 0.6, y + 8, w * 0.38, 14),
            format: PdfStringFormat(alignment: PdfTextAlignment.right));
        y += 34;
      }
      y += 8;
    }

    // ── Top categories ────────────────────────────────────────────────────────
    // Add new page if near bottom
    final PdfPage catPage;
    final PdfGraphics cg;
    if (h - y < 120) {
      catPage = doc.pages.add();
      cg = catPage.graphics;
      y = 0;
    } else {
      catPage = page;
      cg = g;
    }

    if (report.topCategories.isNotEmpty) {
      cg.drawString('Top Categories', secFont,
          brush: PdfSolidBrush(_ink), bounds: Rect.fromLTWH(0, y, w, 18));
      y += 22;
      final maxAmt = report.topCategories.first.amount;
      final barColors = [
        PdfColor(68, 198, 105),
        PdfColor(74, 211, 245),
        PdfColor(184, 125, 233),
        PdfColor(255, 136, 110),
        PdfColor(189, 221, 52),
      ];
      for (var i = 0; i < report.topCategories.length; i++) {
        final cat   = report.topCategories[i];
        final frac  = maxAmt > 0 ? (cat.amount / maxAmt) : 0.0;
        final barW  = (w - 120) * frac;
        final color = barColors[i % barColors.length];

        cg.drawString(cat.label, labelFont,
            brush: PdfSolidBrush(_ink), bounds: Rect.fromLTWH(0, y, 118, 14));
        if (barW > 0) {
          cg.drawRectangle(
              brush: PdfSolidBrush(color),
              bounds: Rect.fromLTWH(122, y + 1, barW, 10));
        }
        cg.drawString('$iso ${_fmt(cat.amount)}', smallFont,
            brush: PdfSolidBrush(_gray),
            bounds: Rect.fromLTWH(w - 80, y, 80, 14),
            format: PdfStringFormat(alignment: PdfTextAlignment.right));
        y += 20;
      }
      y += 8;
    }

    // ── Insight ───────────────────────────────────────────────────────────────
    if (report.reportsGeneratedCount > 0) {
      y += 6;
      final txt =
          'Report #${report.reportsGeneratedCount}'
          '${report.mostActiveWeekday != null ? '  |  Most active: ${_wd(report.mostActiveWeekday!)}' : ''}';
      cg.drawString(txt, smallFont,
          brush: PdfSolidBrush(_gray), bounds: Rect.fromLTWH(0, y, w, 14));
    }

    // ── Footer ────────────────────────────────────────────────────────────────
    final lastPage = doc.pages[doc.pages.count - 1];
    final fg       = lastPage.graphics;
    final fw       = lastPage.getClientSize().width;
    final fh       = lastPage.getClientSize().height;

    fg.drawLine(PdfPen(PdfColor(208, 208, 208)),
        Offset(0, fh - 22), Offset(fw, fh - 22));
    fg.drawString(
      'Generated by SpendAnt  ·  ${DateFormat('MMM d, y HH:mm').format(report.generatedAt)}',
      smallFont,
      brush: PdfSolidBrush(_gray),
      bounds: Rect.fromLTWH(0, fh - 16, fw, 14),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );

    final bytes = Uint8List.fromList(doc.saveSync());
    doc.dispose();
    return bytes;
  }

  // ---------------------------------------------------------------------------

  static void _drawHistogram(
    PdfGraphics g,
    List<DailySpend> days,
    Rect bounds,
  ) {
    if (days.isEmpty) return;
    final maxAmt = days.fold<double>(0, (m, d) => d.amount > m ? d.amount : m);
    if (maxAmt == 0) return;
    final barW = bounds.width / days.length * 0.65;
    final gap  = bounds.width / days.length;
    for (var i = 0; i < days.length; i++) {
      final barH = (days[i].amount / maxAmt) * (bounds.height - 14);
      final x    = bounds.left + i * gap + (gap - barW) / 2;
      final yTop = bounds.top + bounds.height - 14 - barH;
      g.drawRectangle(
          brush: PdfSolidBrush(_green),
          bounds: Rect.fromLTWH(x, yTop, barW, barH));
    }
  }

  // ---------------------------------------------------------------------------

  static Future<String?> _save(FinancialReport report, Uint8List bytes) async {
    final String dir;
    if (Platform.isAndroid) {
      dir = '/storage/emulated/0/Download';
    } else {
      dir = '/tmp';
    }

    final folder = Directory(dir);
    if (!folder.existsSync()) folder.createSync(recursive: true);

    final ts   = DateFormat('yyyyMMdd_HHmm').format(report.generatedAt);
    final file = File(p.join(dir, 'SpendAnt_Report_$ts.pdf'));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static String _fmt(double v) {
    if (v >= 1000) return NumberFormat('#,###', 'en_US').format(v.round());
    return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)
        .replaceAll(RegExp(r'\.?0+$'), '');
  }

  static String _wd(int d) {
    const n = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return d >= 1 && d <= 7 ? n[d] : '';
  }
}
