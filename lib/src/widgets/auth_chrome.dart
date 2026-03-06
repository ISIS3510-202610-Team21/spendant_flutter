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
        Text('SpendAnt', style: titleStyle),
        Transform.translate(
          offset: const Offset(0, -6),
          child: Text(
            'Your Finance Pal',
            style: GoogleFonts.nunito(
              fontSize: large ? 14 : 12,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w700,
              color: AppPalette.ink,
            ),
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
  });

  final Widget child;
  final bool useSafeArea;

  @override
  Widget build(BuildContext context) {
    final content = SizedBox.expand(child: child);
    return Scaffold(
      backgroundColor: AppPalette.green,
      body: useSafeArea ? SafeArea(child: content) : content,
    );
  }
}

class BlackPrimaryButton extends StatelessWidget {
  const BlackPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.width = 206,
    this.height = 46,
  });

  final String label;
  final VoidCallback onPressed;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(onPressed: onPressed, child: Text(label)),
    );
  }
}
