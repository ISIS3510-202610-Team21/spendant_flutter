import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/spendant_theme.dart';

Future<bool> showSpendAntDeleteDialog(
  BuildContext context, {
  required String title,
  required String name,
  String confirmLabel = 'Delete',
}) async {
  final shouldDelete = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return _SpendAntDeleteDialog(
        title: title,
        name: name,
        confirmLabel: confirmLabel,
      );
    },
  );

  return shouldDelete ?? false;
}

class _SpendAntDeleteDialog extends StatelessWidget {
  const _SpendAntDeleteDialog({
    required this.title,
    required this.name,
    required this.confirmLabel,
  });

  final String title;
  final String name;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
        decoration: BoxDecoration(
          color: AppPalette.field,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppPalette.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Are you sure you want to delete "$name"? This action cannot be undone.',
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppPalette.fieldHint,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.fieldHint,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    confirmLabel,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppPalette.ink,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
