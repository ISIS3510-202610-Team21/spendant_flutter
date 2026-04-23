import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/spendant_theme.dart';

class AntAsset extends StatelessWidget {
  const AntAsset(
    this.assetPath, {
    super.key,
    this.height,
    this.fit = BoxFit.contain,
  });

  final String assetPath;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(assetPath, height: height, fit: fit);
  }
}

class SpendAntWordmark extends StatelessWidget {
  const SpendAntWordmark({super.key, this.large = true});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final titleStyle = large
        ? Theme.of(context).textTheme.displayLarge
        : Theme.of(context).textTheme.displaySmall;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('SpendAnt', textAlign: TextAlign.center, style: titleStyle),
        const SizedBox(height: 2),
        Text(
          'Your Finance Pal',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(
            fontSize: large ? 18 : 16,
            fontWeight: FontWeight.w700,
            color: AppPalette.ink,
          ),
        ),
      ],
    );
  }
}

class GreenScreenScaffold extends StatelessWidget {
  const GreenScreenScaffold({
    super.key,
    required this.child,
    this.useSafeArea = true,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget child;
  final bool useSafeArea;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final content = SizedBox.expand(child: child);
    return Scaffold(
      backgroundColor: AppPalette.green,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: useSafeArea ? SafeArea(child: content) : content,
    );
  }
}

class BlackPrimaryButton extends StatelessWidget {
  static const _defaultBorderRadius = AppRadius.card;

  const BlackPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.width = 206,
    this.height = 46,
    this.isLoading = false,
    this.padding,
    this.borderRadius,
    this.tapTargetSize,
  });

  final String label;
  final VoidCallback? onPressed;
  final double? width;
  final double height;
  final bool isLoading;
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry? borderRadius;
  final MaterialTapTargetSize? tapTargetSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          minimumSize: Size(0, height),
          padding: padding,
          tapTargetSize: tapTargetSize,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius ?? _defaultBorderRadius,
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppPalette.white),
                ),
              )
            : Text(label),
      ),
    );
  }
}
