import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../theme/spendant_theme.dart';

class NewExpenseScreen extends StatefulWidget {
  const NewExpenseScreen({super.key});

  @override
  State<NewExpenseScreen> createState() => _NewExpenseScreenState();
}

class _NewExpenseScreenState extends State<NewExpenseScreen> {
  final TextEditingController _expenseNameController = TextEditingController();
  final TextEditingController _expenseValueController = TextEditingController();
  final List<String> _labels = <String>[];

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  ExpenseLocationSelection? _selectedLocation;
  bool _isRecurring = false;
  String _recurringFrequency = 'Monthly';

  @override
  void dispose() {
    _expenseNameController.dispose();
    _expenseValueController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    DateTime tempDate = _selectedDate;

    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return _PickerSheet(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select date',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    DateFormat('EEE, MMM d').format(tempDate),
                    style: GoogleFonts.nunito(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CalendarDatePicker(
                    initialDate: tempDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                    onDateChanged: (value) {
                      setSheetState(() {
                        tempDate = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(tempDate),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _selectedDate = selected;
    });
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: AppPalette.green),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _selectedTime = selected;
    });
  }

  Future<void> _pickLocation() async {
    final selected = await Navigator.of(context).push<ExpenseLocationSelection>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initialValue: _selectedLocation),
      ),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _selectedLocation = selected;
    });
  }

  Future<void> _addLabel() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('New label'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'e.g. Transport'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (label == null || label.isEmpty) {
      return;
    }

    setState(() {
      if (!_labels.contains(label)) {
        _labels.add(label);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _ExpenseHeader(
                  onClose: () => Navigator.of(context).maybePop(),
                  onConfirm: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      28,
                      24,
                      140 + keyboardInset,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: OutlinedButton(
                            onPressed: _pickDate,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.black26),
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Today',
                              style: GoogleFonts.nunito(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _ExpenseField(
                          controller: _expenseNameController,
                          hintText: 'Expense name',
                        ),
                        const SizedBox(height: 10),
                        _ExpenseField(
                          controller: _expenseValueController,
                          hintText: r'$ 0.00',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final label in _labels)
                              Chip(
                                label: Text(label),
                                onDeleted: () {
                                  setState(() {
                                    _labels.remove(label);
                                  });
                                },
                                backgroundColor: AppPalette.green.withValues(
                                  alpha: 0.85,
                                ),
                                labelStyle: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.ink,
                                ),
                              ),
                            _MiniActionButton(
                              icon: Icons.add,
                              label: 'Label',
                              onPressed: _addLabel,
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.field,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Recurring expense',
                                      style: GoogleFonts.nunito(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: AppPalette.ink,
                                      ),
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: _isRecurring,
                                    activeThumbColor: AppPalette.green,
                                    activeTrackColor: AppPalette.green
                                        .withValues(alpha: 0.45),
                                    onChanged: (value) {
                                      setState(() {
                                        _isRecurring = value;
                                      });
                                    },
                                  ),
                                ],
                              ),
                              if (_isRecurring)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Wrap(
                                    spacing: 8,
                                    children: [
                                      for (final frequency in const [
                                        'Daily',
                                        'Weekly',
                                        'Monthly',
                                      ])
                                        ChoiceChip(
                                          selected:
                                              _recurringFrequency == frequency,
                                          label: Text(frequency),
                                          onSelected: (_) {
                                            setState(() {
                                              _recurringFrequency = frequency;
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        Center(
                          child: SizedBox(
                            width: 136,
                            child: ElevatedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.document_scanner_outlined),
                              label: const Text('Scan Receipt'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 12,
                                ),
                                textStyle: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
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
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            bottom: keyboardInset,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F3F3),
                  border: Border(top: BorderSide(color: Colors.black12)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _MetaChip(
                        icon: Icons.calendar_today_outlined,
                        label: DateFormat('d/M/y').format(_selectedDate),
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MetaChip(
                        icon: Icons.access_time,
                        label: _selectedTime.format(context).toLowerCase(),
                        onTap: _pickTime,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MetaChip(
                        icon: Icons.location_on_outlined,
                        label: _selectedLocation?.label ?? 'Pick location',
                        onTap: _pickLocation,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ExpenseLocationSelection {
  const ExpenseLocationSelection({required this.position, required this.label});

  final LatLng position;
  final String label;
}

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initialValue});

  final ExpenseLocationSelection? initialValue;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const LatLng _defaultCenter = LatLng(4.60971, -74.08175);

  late LatLng _selectedPoint = widget.initialValue?.position ?? _defaultCenter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _selectedPoint,
                    zoom: 16,
                  ),
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  onTap: (point) {
                    setState(() {
                      _selectedPoint = point;
                    });
                  },
                  markers: {
                    Marker(
                      markerId: const MarkerId('selected-location'),
                      position: _selectedPoint,
                    ),
                  },
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: TextField(
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'Search label',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 18,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        ExpenseLocationSelection(
                          position: _selectedPoint,
                          label:
                              '${_selectedPoint.latitude.toStringAsFixed(4)}, ${_selectedPoint.longitude.toStringAsFixed(4)}',
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.green,
                      foregroundColor: AppPalette.ink,
                    ),
                    child: Text(
                      'Save',
                      style: GoogleFonts.nunito(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpenseHeader extends StatelessWidget {
  const _ExpenseHeader({required this.onClose, required this.onConfirm});

  final VoidCallback onClose;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppPalette.green,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: AppPalette.ink),
          ),
          Expanded(
            child: Text(
              'New Expense',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppPalette.ink,
              ),
            ),
          ),
          IconButton(
            onPressed: onConfirm,
            icon: const Icon(Icons.check, color: AppPalette.ink),
          ),
        ],
      ),
    );
  }
}

class _ExpenseField extends StatelessWidget {
  const _ExpenseField({
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        hintText: hintText,
        fillColor: AppPalette.field,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(0),
          borderSide: BorderSide.none,
        ),
      ),
      style: GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppPalette.ink,
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppPalette.ink),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: AppPalette.green,
          foregroundColor: AppPalette.ink,
          elevation: 0,
          textStyle: GoogleFonts.nunito(
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        color: AppPalette.field,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: child,
        ),
      ),
    );
  }
}
