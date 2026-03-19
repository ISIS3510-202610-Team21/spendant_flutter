import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/spendant_theme.dart';

class ProfileEditResult {
  const ProfileEditResult({required this.name, required this.avatarBase64});

  final String name;
  final String? avatarBase64;
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.initialName,
    this.initialAvatarBase64,
  });

  final String initialName;
  final String? initialAvatarBase64;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName,
  );
  late String? _avatarBase64 = widget.initialAvatarBase64;
  Uint8List? _avatarBytes;

  @override
  void initState() {
    super.initState();
    _avatarBytes = _decodeAvatar(widget.initialAvatarBase64);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Uint8List? _decodeAvatar(String? avatarBase64) {
    if (avatarBase64 == null || avatarBase64.isEmpty) {
      return null;
    }

    try {
      return base64Decode(avatarBase64);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickProfileImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 720,
      );
      if (image == null) {
        return;
      }

      final bytes = await image.readAsBytes();
      if (!mounted) {
        return;
      }

      setState(() {
        _avatarBytes = bytes;
        _avatarBase64 = base64Encode(bytes);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The profile picture could not be loaded'),
        ),
      );
    }
  }

  void _save() {
    final trimmedName = _nameController.text.trim();
    if (trimmedName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a username')));
      return;
    }

    Navigator.of(
      context,
    ).pop(ProfileEditResult(name: trimmedName, avatarBase64: _avatarBase64));
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: AppPalette.green,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppPalette.ink),
                  ),
                  Expanded(
                    child: Text(
                      'Profile',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _save,
                    icon: const Icon(Icons.check, color: AppPalette.ink),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 36 + keyboardInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickProfileImage,
                      borderRadius: BorderRadius.circular(80),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 38,
                            backgroundColor: const Color(0xFFFFCCBB),
                            backgroundImage: _avatarBytes != null
                                ? MemoryImage(_avatarBytes!)
                                : null,
                            child: _avatarBytes == null
                                ? const Icon(
                                    Icons.person_outline,
                                    color: Color(0xFFFF6E40),
                                    size: 42,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Change Profile Picture',
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Username',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      decoration: const BoxDecoration(
                        color: AppPalette.field,
                        border: Border(
                          bottom: BorderSide(color: AppPalette.ink, width: 1.3),
                        ),
                      ),
                      child: TextField(
                        controller: _nameController,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 130),
                    Center(
                      child: SizedBox(
                        width: 96,
                        height: 42,
                        child: ElevatedButton(
                          onPressed: _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppPalette.ink,
                            foregroundColor: Colors.white,
                            textStyle: GoogleFonts.nunito(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child: const Text('Save'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
