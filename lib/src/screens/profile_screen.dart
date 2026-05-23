import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app.dart';
import '../services/auth_memory_store.dart';
import '../services/currency_provider.dart';
import '../services/local_storage_service.dart';
import '../theme/spendant_theme.dart';
import '../widgets/auth_chrome.dart';
import '../widgets/no_internet_banner.dart';
import '../widgets/spendant_bottom_nav.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _profileName = 'John Doe';
  String _profileHandle = '@johndoe';
  Uint8List? _profileAvatarBytes;
  String? _profileAvatarBase64;

  int get _currentUserId => AuthMemoryStore.currentUserIdOrGuest;

  @override
  void initState() {
    super.initState();
    _loadProfileIdentity();
  }

  // ---------------------------------------------------------------------------
  // Identity helpers (same logic as SetGoalScreen)
  // ---------------------------------------------------------------------------

  Future<void> _loadProfileIdentity() async {
    final authState = await AuthMemoryStore.loadGreetingState();
    final currentUser = LocalStorageService().getUserById(_currentUserId);
    final rawName = currentUser?.displayName?.trim().isNotEmpty == true
        ? currentUser!.displayName!.trim()
        : authState.username?.trim();
    final avatarBase64 = currentUser?.avatarPath?.trim().isNotEmpty == true
        ? currentUser!.avatarPath!.trim()
        : authState.avatarBase64;
    final displayName =
        rawName == null || rawName.isEmpty ? 'John Doe' : rawName;

    if (!mounted) return;

    setState(() {
      _profileName = displayName;
      _profileHandle = _buildHandle(displayName);
      _profileAvatarBase64 = avatarBase64;
      _profileAvatarBytes = _decodeAvatar(avatarBase64);
    });
  }

  Uint8List? _decodeAvatar(String? avatarBase64) {
    if (avatarBase64 == null || avatarBase64.isEmpty) return null;
    try {
      return base64Decode(avatarBase64);
    } catch (_) {
      return null;
    }
  }

  String _buildHandle(String name) {
    final normalized = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return '@${normalized.isEmpty ? 'spendant' : normalized}';
  }

  void _openCurrencyConverter(BuildContext context) {
    // Guard: if rates were never downloaded (only COP in cache = no connectivity),
    // block navigation to avoid showing "1 USD = 1 COP" everywhere.
    final ratesLoaded = CurrencyProvider.instance.ratesCache.length > 1;
    if (!ratesLoaded) {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
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
                  'Rates not available',
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Exchange rates could not be downloaded. Connect to the internet and reopen the app to enable currency conversion.',
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
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Got it',
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pushNamed(AppRoutes.currencyConverter);
  }

  Future<void> _openProfileEditor() async {
    final updatedProfile = await Navigator.of(context).push<ProfileEditResult>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          initialName: _profileName,
          initialAvatarBase64: _profileAvatarBase64,
        ),
      ),
    );

    if (updatedProfile == null || !mounted) return;

    final trimmedName = updatedProfile.name.trim();
    if (trimmedName.isEmpty) return;

    final currentUser = LocalStorageService().getUserById(_currentUserId);
    if (currentUser != null) {
      currentUser
        ..username = trimmedName
        ..displayName = trimmedName
        ..handle = _buildHandle(trimmedName)
        ..avatarPath = updatedProfile.avatarBase64
        ..isSynced = false;
      await currentUser.save();
    }
    await AuthMemoryStore.saveProfile(
      username: trimmedName,
      avatarBase64: updatedProfile.avatarBase64,
    );
    if (!mounted) return;

    setState(() {
      _profileName = trimmedName;
      _profileHandle = _buildHandle(trimmedName);
      _profileAvatarBase64 = updatedProfile.avatarBase64;
      _profileAvatarBytes = _decodeAvatar(updatedProfile.avatarBase64);
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          const SpendAntBottomNav(currentItem: SpendAntNavItem.profile),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompactHeight = constraints.maxHeight < 760;
        final antHeight = isCompactHeight ? 180.0 : 270.0;
        final topPadding = isCompactHeight ? 20.0 : 30.0;
        final antTopSpacing = isCompactHeight ? 64.0 : 112.0;

        final content = Column(
          children: [
            // ── Green header ─────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 58, 20, 34),
              decoration: const BoxDecoration(
                color: AppPalette.green,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 32, height: 32),
                      Expanded(
                        child: Text(
                          'Profile',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppPalette.ink,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _openProfileEditor,
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: AppPalette.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: const Color(0xFFFFCCBB),
                    backgroundImage: _profileAvatarBytes != null
                        ? MemoryImage(_profileAvatarBytes!)
                        : null,
                    child: _profileAvatarBytes == null
                        ? const Icon(
                            Icons.person,
                            color: Color(0xFFFF9999),
                            size: 45,
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _profileName,
                    style: GoogleFonts.nunito(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    _profileHandle,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const NoInternetBanner(),
            SizedBox(height: topPadding),
            // ── 2 × 2 action button grid ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _actionButton(
                          'Income',
                          assetPath: 'web/icons/IncomeWhite.svg',
                          onPressed: () =>
                              Navigator.of(context).pushNamed(AppRoutes.budget),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _actionButton(
                          'Goals',
                          icon: Icons.flag_outlined,
                          onPressed: () => Navigator.of(context).pushNamed(
                            AppRoutes.setGoal,
                            arguments: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _actionButton(
                          'Currency',
                          assetPath: 'web/icons/CurrencyConverter.svg',
                          onPressed: () => _openCurrencyConverter(context),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _actionButton(
                          'Summary',
                          assetPath: 'web/icons/PDF.svg',
                          onPressed: () => Navigator.of(context).pushNamed(
                            AppRoutes.reportSetup,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: antTopSpacing),
            // ── Ant mascot ───────────────────────────────────────────────────
            Center(
              child: SizedBox(
                width: isCompactHeight ? 150 : 200,
                height: antHeight,
                child: const AntAsset('web/ant/ant_idle.svg'),
              ),
            ),
            SizedBox(height: isCompactHeight ? 28 : 40),
          ],
        );

        return SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: content,
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Action button (same visual style as SetGoalScreen._profileActionButton)
  // ---------------------------------------------------------------------------

  Widget _actionButton(
    String label, {
    IconData? icon,
    String? assetPath,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: assetPath != null
          ? SvgPicture.asset(
              assetPath,
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            )
          : Icon(icon, size: 20, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
    );
  }
}
