import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../theme/spendant_theme.dart';

class _ExpenseLabelOption {
  const _ExpenseLabelOption({required this.label, required this.color});

  final String label;
  final Color color;
}

class NewExpenseScreen extends StatefulWidget {
  const NewExpenseScreen({super.key});

  @override
  State<NewExpenseScreen> createState() => _NewExpenseScreenState();
}

class _NewExpenseScreenState extends State<NewExpenseScreen> {
  final TextEditingController _expenseNameController = TextEditingController();
  final TextEditingController _expenseValueController = TextEditingController();
  final List<String> _selectedLabels = <String>[];
  final List<String> _customLabels = <String>[];

  static const List<_ExpenseLabelOption> _predefinedLabels =
      <_ExpenseLabelOption>[
        _ExpenseLabelOption(label: 'Food', color: AppPalette.food),
        _ExpenseLabelOption(label: 'Transport', color: AppPalette.transport),
        _ExpenseLabelOption(label: 'Services', color: AppPalette.services),
        _ExpenseLabelOption(label: 'Other', color: AppPalette.other),
      ];

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  ExpenseLocationSelection? _selectedLocation;

  @override
  void dispose() {
    _expenseNameController.dispose();
    _expenseValueController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) => DateSelectionScreen(initialDate: _selectedDate),
      ),
    );

    if (selected != null) {
      setState(() {
        _selectedDate = selected;
      });
    }
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        if (child == null) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: AppPalette.green,
              onPrimary: AppPalette.ink,
              surface: Colors.white,
              onSurface: AppPalette.ink,
            ),
          ),
          child: child,
        );
      },
    );

    if (selected != null) {
      setState(() {
        _selectedTime = selected;
      });
    }
  }

  Future<void> _pickLocation() async {
    final selected = await Navigator.of(context).push<ExpenseLocationSelection>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initialValue: _selectedLocation),
      ),
    );

    if (selected != null) {
      setState(() {
        _selectedLocation = selected;
      });
    }
  }

  String _normalizeLabel(String value) => value.trim().toLowerCase();

  bool _containsLabel(List<String> labels, String candidate) {
    final normalizedCandidate = _normalizeLabel(candidate);
    return labels.any((label) => _normalizeLabel(label) == normalizedCandidate);
  }

  _ExpenseLabelOption? _matchingPredefinedLabel(String label) {
    for (final option in _predefinedLabels) {
      if (_normalizeLabel(option.label) == _normalizeLabel(label)) {
        return option;
      }
    }
    return null;
  }

  bool _isLabelSelected(String label) => _containsLabel(_selectedLabels, label);

  void _togglePredefinedLabel(String label) {
    final isSelected = _isLabelSelected(label);
    setState(() {
      if (isSelected) {
        _selectedLabels.removeWhere(
          (selected) => _normalizeLabel(selected) == _normalizeLabel(label),
        );
        return;
      }
      _selectedLabels.add(label);
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
          title: Text(
            'New label',
            style: GoogleFonts.nunito(fontWeight: FontWeight.w900),
          ),
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

    final predefinedMatch = _matchingPredefinedLabel(label);
    final resolvedLabel = predefinedMatch?.label ?? label;

    if (_containsLabel(_selectedLabels, resolvedLabel)) {
      return;
    }

    setState(() {
      if (predefinedMatch == null &&
          !_containsLabel(_customLabels, resolvedLabel)) {
        _customLabels.add(resolvedLabel);
      }
      _selectedLabels.add(resolvedLabel);
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _ExpenseHeader(
                  title: 'New Expense',
                  onClose: () => Navigator.of(context).maybePop(),
                  onConfirm: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      28,
                      24,
                      136 + keyboardInset,
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
                            for (final option in _predefinedLabels)
                              FilterChip(
                                label: Text(option.label),
                                selected: _isLabelSelected(option.label),
                                showCheckmark: false,
                                onSelected: (_) =>
                                    _togglePredefinedLabel(option.label),
                                backgroundColor: option.color.withValues(
                                  alpha: 0.16,
                                ),
                                selectedColor: option.color.withValues(
                                  alpha: 0.72,
                                ),
                                side: BorderSide(
                                  color: option.color.withValues(alpha: 0.5),
                                ),
                                labelStyle: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.ink,
                                ),
                              ),
                            for (final label in _customLabels)
                              Chip(
                                label: Text(label),
                                onDeleted: () {
                                  setState(() {
                                    _customLabels.removeWhere(
                                      (customLabel) =>
                                          _normalizeLabel(customLabel) ==
                                          _normalizeLabel(label),
                                    );
                                    _selectedLabels.removeWhere(
                                      (selectedLabel) =>
                                          _normalizeLabel(selectedLabel) ==
                                          _normalizeLabel(label),
                                    );
                                  });
                                },
                                backgroundColor: AppPalette.other.withValues(
                                  alpha: 0.72,
                                ),
                                deleteIconColor: AppPalette.ink,
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
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.black12)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
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

class DateSelectionScreen extends StatefulWidget {
  const DateSelectionScreen({super.key, required this.initialDate});

  final DateTime initialDate;

  @override
  State<DateSelectionScreen> createState() => _DateSelectionScreenState();
}

class _DateSelectionScreenState extends State<DateSelectionScreen> {
  late DateTime _visibleMonth = DateTime(
    widget.initialDate.year,
    widget.initialDate.month,
  );
  late DateTime _selectedDate = widget.initialDate;

  Future<void> _selectMonth() async {
    final selectedMonth = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: 12,
            itemBuilder: (context, index) {
              final month = index + 1;
              return ListTile(
                title: Text(
                  DateFormat('MMMM').format(DateTime(2026, month)),
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w800,
                    color: AppPalette.ink,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(month),
              );
            },
          ),
        );
      },
    );

    if (selectedMonth == null) {
      return;
    }

    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, selectedMonth);
      _selectedDate = _clampDateToVisibleMonth(_selectedDate, _visibleMonth);
    });
  }

  Future<void> _selectYear() async {
    final years = List<int>.generate(21, (index) => 2020 + index);
    final selectedYear = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final year in years)
                ListTile(
                  title: Text(
                    '$year',
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w800,
                      color: AppPalette.ink,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(year),
                ),
            ],
          ),
        );
      },
    );

    if (selectedYear == null) {
      return;
    }

    setState(() {
      _visibleMonth = DateTime(selectedYear, _visibleMonth.month);
      _selectedDate = _clampDateToVisibleMonth(_selectedDate, _visibleMonth);
    });
  }

  DateTime _clampDateToVisibleMonth(DateTime value, DateTime visibleMonth) {
    final lastDay = DateUtils.getDaysInMonth(
      visibleMonth.year,
      visibleMonth.month,
    );
    return DateTime(
      visibleMonth.year,
      visibleMonth.month,
      math.min(value.day, lastDay),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _ExpenseHeader(
              title: 'Select Date',
              onClose: () => Navigator.of(context).pop(),
              onConfirm: () => Navigator.of(context).pop(_selectedDate),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  decoration: BoxDecoration(
                    color: AppPalette.field,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select date',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.fieldHint,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        DateFormat('EEE, MMM d').format(_selectedDate),
                        style: GoogleFonts.nunito(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _SelectionPill(
                            label: DateFormat('MMMM').format(_visibleMonth),
                            onTap: _selectMonth,
                          ),
                          const SizedBox(width: 8),
                          _SelectionPill(
                            label: '${_visibleMonth.year}',
                            onTap: _selectYear,
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _visibleMonth = DateTime(
                                  _visibleMonth.year,
                                  _visibleMonth.month - 1,
                                );
                                _selectedDate = _clampDateToVisibleMonth(
                                  _selectedDate,
                                  _visibleMonth,
                                );
                              });
                            },
                            icon: const Icon(Icons.chevron_left),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _visibleMonth = DateTime(
                                  _visibleMonth.year,
                                  _visibleMonth.month + 1,
                                );
                                _selectedDate = _clampDateToVisibleMonth(
                                  _selectedDate,
                                  _visibleMonth,
                                );
                              });
                            },
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: CalendarDatePicker(
                          initialDate: _selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2040),
                          currentDate: DateTime.now(),
                          onDateChanged: (value) {
                            setState(() {
                              _selectedDate = value;
                              _visibleMonth = DateTime(value.year, value.month);
                            });
                          },
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Close',
                              style: GoogleFonts.nunito(
                                fontWeight: FontWeight.w800,
                                color: AppPalette.green,
                              ),
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.nunito(
                                fontWeight: FontWeight.w800,
                                color: AppPalette.green,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.of(context).pop(_selectedDate),
                            child: Text(
                              'OK',
                              style: GoogleFonts.nunito(
                                fontWeight: FontWeight.w900,
                                color: AppPalette.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    final label =
        '${_selectedPoint.latitude.toStringAsFixed(4)}, ${_selectedPoint.longitude.toStringAsFixed(4)}';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _ExpenseHeader(
              title: 'Select Location',
              onClose: () => Navigator.of(context).pop(),
              onConfirm: () {
                Navigator.of(context).pop(
                  ExpenseLocationSelection(
                    position: _selectedPoint,
                    label: label,
                  ),
                );
              },
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: Column(
                  children: [
                    TextField(
                      readOnly: true,
                      decoration: InputDecoration(
                        hintText: 'Search label',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: const Icon(Icons.location_on_outlined),
                        fillColor: Colors.white,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          color: AppPalette.field,
                          child: Stack(
                            children: [
                              Positioned.fill(child: _buildMapSurface()),
                              Positioned(
                                left: 16,
                                right: 16,
                                bottom: 16,
                                child: Center(
                                  child: SizedBox(
                                    width: 120,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        Navigator.of(context).pop(
                                          ExpenseLocationSelection(
                                            position: _selectedPoint,
                                            label: label,
                                          ),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppPalette.green,
                                        foregroundColor: AppPalette.ink,
                                      ),
                                      child: Text(
                                        'Save',
                                        style: GoogleFonts.nunito(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
    );
  }

  Widget _buildMapSurface() {
    if (kIsWeb) {
      return Container(
        color: const Color(0xFFEDEDED),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          'Google Maps on web needs a configured JavaScript API key. The crash is blocked for now, and you can still save the current point.',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppPalette.ink,
          ),
        ),
      );
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: _selectedPoint, zoom: 16),
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
    );
  }
}

class _ExpenseHeader extends StatelessWidget {
  const _ExpenseHeader({
    required this.title,
    required this.onClose,
    required this.onConfirm,
  });

  final String title;
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
              title,
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
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
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
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppPalette.ink),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.ink,
                  ),
                ),
              ),
            ],
          ),
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

class _SelectionPill extends StatelessWidget {
  const _SelectionPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppPalette.ink,
          ),
        ),
      ),
    );
  }
}
