import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/voice_parse_result.dart';
import '../services/currency_provider.dart';
import '../services/voice_pipeline_service.dart';
import '../theme/spendant_theme.dart';

class VoiceRegisterScreen extends StatefulWidget {
  const VoiceRegisterScreen({super.key});

  @override
  State<VoiceRegisterScreen> createState() => _VoiceRegisterScreenState();
}

class _VoiceRegisterScreenState extends State<VoiceRegisterScreen>
    with SingleTickerProviderStateMixin {

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  bool _isListening = false;
  bool _isParsing = false;
  String? _rawTranscription;
  VoiceParseResult? _parseResult;
  String? _errorMessage;

  // Normalized RMS amplitude [0.0 – 1.0] streamed from Android SpeechRecognizer.
  // Smoothed with exponential decay to avoid jitter.
  double _amplitude = 0.0;
  StreamSubscription<double>? _rmsSub;

  // Subtle pulse for the mic button circle.
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  // Drives the WhatsApp-style waveform bars (20 bars, staggered sin phases).
  late final AnimationController _waveController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void dispose() {
    _rmsSub?.cancel();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Pipeline actions
  // ---------------------------------------------------------------------------

  Future<void> _onMicTap() async {
    if (_isListening) {
      // Stop early — triggers onResults on the Android side.
      await VoicePipelineService.stopListening();
      return;
    }

    // Request microphone permission before starting.
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() => _errorMessage = 'Microphone permission denied.');
      }
      return;
    }

    // ── Stage 1 + 2: Android STT ────────────────────────────────────────────
    setState(() {
      _isListening = true;
      _errorMessage = null;
    });
    _pulseController.repeat(reverse: true);
    _waveController.repeat();

    // Subscribe to real-time RMS from Android — drives waveform bar heights.
    _rmsSub = VoicePipelineService.rmsStream.listen((raw) {
      if (!mounted) return;
      setState(() {
        // Exponential smoothing: fast rise, slow decay for natural feel.
        _amplitude = _amplitude * 0.55 + raw * 0.45;
      });
    });

    final rawText = await VoicePipelineService.startListening();

    _pulseController.stop();
    _pulseController.reset();
    _waveController.stop();
    _waveController.reset();
    _rmsSub?.cancel();
    _rmsSub = null;
    if (mounted) setState(() => _amplitude = 0.0);

    if (!mounted) return;

    if (rawText == null || rawText.trim().isEmpty) {
      setState(() {
        _isListening = false;
        _errorMessage = 'Nothing was recognized. Try again.';
      });
      return;
    }

    setState(() {
      _isListening = false;
      _isParsing = true;
      _rawTranscription = rawText;
    });

    // ── Stage 3: Entity Parsing (Isolate.run + cache) ────────────────────────
    final result = await VoicePipelineService.parseAndCache(rawText);

    if (!mounted) return;

    setState(() {
      _isParsing = false;
      _parseResult = result;
      if (result == null) {
        _errorMessage =
            'Could not extract an expense from what you said. Try: "I paid 15 dollars for coffee."';
      }
    });
  }

  void _confirm() {
    if (_parseResult == null) return;
    Navigator.of(context).pop(_parseResult);
  }

  void _cancel() => Navigator.of(context).pop();

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
            _buildAppBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildInstructionsCard(),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      _buildErrorBanner(),
                    ],
                    if (_rawTranscription != null) ...[
                      const SizedBox(height: 24),
                      _buildPreviewSection(),
                    ],
                  ],
                ),
              ),
            ),
            _buildMicButton(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AppBar
  // ---------------------------------------------------------------------------

  Widget _buildAppBar() {
    final confirmActive = _parseResult != null && !_isParsing;
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
          ),
          Expanded(
            child: Text(
              'Voice Register',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppPalette.ink,
              ),
            ),
          ),
          IconButton(
            onPressed: confirmActive ? _confirm : null,
            icon: Icon(
              Icons.check,
              color: confirmActive ? AppPalette.ink : AppPalette.ink.withValues(alpha: 0.3),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Instructions card
  // ---------------------------------------------------------------------------

  static final _instructionStyle = GoogleFonts.nunito(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppPalette.ink,
    height: 1.5,
  );

  static final _exampleStyle = GoogleFonts.nunito(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontStyle: FontStyle.italic,
    color: AppPalette.fieldHint,
    height: 1.4,
  );

  Widget _buildInstructionsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.field,
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Say your expense in this format:',
            textAlign: TextAlign.center,
            style: _instructionStyle,
          ),
          const SizedBox(height: 10),
          Text(
            '"I paid [amount] for [product] (on [day]) (at [time]) (at [location])"',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppPalette.ink,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Text('For example:', textAlign: TextAlign.center, style: _instructionStyle),
          const SizedBox(height: 8),
          Text(
            '"I paid 5 dollars for coffee"',
            textAlign: TextAlign.center,
            style: _exampleStyle,
          ),
          const SizedBox(height: 4),
          Text(
            '"I paid 15 euros for lunch yesterday at McDonald\'s"',
            textAlign: TextAlign.center,
            style: _exampleStyle,
          ),
          const SizedBox(height: 4),
          Text(
            '"I paid 25,000 pesos for a taxi on Tuesday at 10 PM at the airport"',
            textAlign: TextAlign.center,
            style: _exampleStyle,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Error banner
  // ---------------------------------------------------------------------------

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppPalette.expenseRed.withValues(alpha: 0.08),
        borderRadius: AppRadius.card,
        border: Border.all(color: AppPalette.expenseRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppPalette.expenseRed, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppPalette.expenseRed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Preview section (conditionally visible)
  // ---------------------------------------------------------------------------

  Widget _buildPreviewSection() {
    final result = _parseResult;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What I heard:',
          style: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppPalette.ink,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppPalette.gray,
            borderRadius: AppRadius.card,
          ),
          child: Text(
            '"${_rawTranscription!}"',
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
              color: AppPalette.fieldHint,
            ),
          ),
        ),
        if (_isParsing) ...[
          const SizedBox(height: 20),
          const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppPalette.green,
            ),
          ),
        ] else if (result != null) ...[
          const SizedBox(height: 20),
          _buildParsedSummary(result),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Looks correct? Save now',
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppPalette.green,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildParsedSummary(VoiceParseResult result) {
    // If user dictated the SAME currency as the active one (or none = default),
    // show plain amount. If they said a DIFFERENT currency, show the active
    // currency equivalent so they know what will be stored.
    final activeCurrency = CurrencyProvider.instance.activeCurrency;
    final String displayAmount;
    if (result.originalCurrency == activeCurrency) {
      displayAmount = '$activeCurrency ${_fmtNum(result.originalAmount)}';
    } else {
      final localAmount =
          CurrencyProvider.instance.convertToLocal(result.convertedAmountCop);
      displayAmount =
          '${result.originalCurrency} ${_fmtNum(result.originalAmount)}'
          '  (≈ $activeCurrency ${_fmtNum(localAmount)})';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.field,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppPalette.green.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summaryRow('Product', result.productName),
          const SizedBox(height: 6),
          _summaryRow('Amount', displayAmount),
          if (result.location != null) ...[
            const SizedBox(height: 6),
            _summaryRow('Location', result.location!),
          ],
          if (result.time != null) ...[
            const SizedBox(height: 6),
            _summaryRow('Time', _to12h(result.time!)),
          ],
          // Only show date when user explicitly mentioned it.
          // If omitted, today is auto-applied — no need to clutter the preview.
          if (result.wasDateExplicit) ...[
            const SizedBox(height: 6),
            _summaryRow(
              'Date',
              '${result.date.year}-${result.date.month.toString().padLeft(2, '0')}-'
              '${result.date.day.toString().padLeft(2, '0')}',
            ),
          ],
        ],
      ),
    );
  }

  /// Formats a number: integer if whole, 2 decimal places otherwise.
  static String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  }

  /// Converts "HH:mm" (24h) to "H:mm AM/PM" for display.
  static String _to12h(String time24) {
    final parts = time24.split(':');
    if (parts.length != 2) return time24;
    final hour24 = int.tryParse(parts[0]);
    final min    = int.tryParse(parts[1]);
    if (hour24 == null || min == null) return time24;
    final suffix = hour24 < 12 ? 'AM' : 'PM';
    final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
    return '$hour12:${min.toString().padLeft(2, '0')} $suffix';
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppPalette.fieldHint,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppPalette.ink,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Mic button
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Mic button + waveform
  // ---------------------------------------------------------------------------

  static const int _barCount = 22;
  static const double _barWidth = 4;
  static const double _barGap = 3;
  static const double _barMaxHeight = 36;
  static const double _barMinHeight = 5;

  Widget _buildMicButton() {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 24,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Waveform (visible only while recording) ──────────────────────
          AnimatedOpacity(
            opacity: _isListening ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              height: _barMaxHeight + 8,
              child: AnimatedBuilder(
                animation: _waveController,
                builder: (context, _) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(_barCount, (i) {
                      // Stagger each bar with a unique sin phase.
                      final phase = i * (2 * math.pi / _barCount);
                      // sin in [0,1]
                      final sinVal =
                          (math.sin(_waveController.value * 2 * math.pi + phase) + 1) / 2;
                      // Height scales with real-time amplitude:
                      //   silence  → all bars at minHeight
                      //   loud     → bars reach up to maxHeight
                      final height = _barMinHeight +
                          sinVal * _amplitude * (_barMaxHeight - _barMinHeight);
                      return Container(
                        width: _barWidth,
                        height: height.clamp(_barMinHeight, _barMaxHeight),
                        margin: const EdgeInsets.symmetric(
                          horizontal: _barGap / 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.green,
                          borderRadius: AppRadius.pill,
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── Mic circle button ─────────────────────────────────────────────
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = _isListening
                  ? 1.0 + (_pulseController.value * 0.08)
                  : 1.0;
              return Transform.scale(scale: scale, child: child);
            },
            child: GestureDetector(
              onTap: _onMicTap,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _isListening
                      ? AppPalette.green.withValues(alpha: 0.85)
                      : AppPalette.green,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppPalette.green.withValues(
                        alpha: _isListening ? 0.5 : 0.25,
                      ),
                      blurRadius: _isListening ? 20 : 8,
                      spreadRadius: _isListening ? 4 : 0,
                    ),
                  ],
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'web/icons/BlackMic.svg',
                    width: 32,
                    height: 32,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
