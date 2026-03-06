import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
    final selected = await Navigator.of(context).push<TimeOfDay>(
      MaterialPageRoute(
        builder: (_) => TimeSelectionScreen(initialTime: _selectedTime),
      ),
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

    if (label == null || label.isEmpty || _labels.contains(label)) {
      return;
    }

    setState(() {
      _labels.add(label);
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

enum _TimeDialMode { hour, minute }

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

class TimeSelectionScreen extends StatefulWidget {
  const TimeSelectionScreen({super.key, required this.initialTime});

  final TimeOfDay initialTime;

  @override
  State<TimeSelectionScreen> createState() => _TimeSelectionScreenState();
}

class _TimeSelectionScreenState extends State<TimeSelectionScreen> {
  late int _hour = widget.initialTime.hourOfPeriod == 0
      ? 12
      : widget.initialTime.hourOfPeriod;
  late int _minute = (widget.initialTime.minute ~/ 5) * 5;
  late bool _isAm = widget.initialTime.period == DayPeriod.am;
  _TimeDialMode _mode = _TimeDialMode.hour;

  TimeOfDay get _selectedTime {
    final hour24 = (_hour % 12) + (_isAm ? 0 : 12);
    return TimeOfDay(hour: hour24, minute: _minute);
  }

  @override
  Widget build(BuildContext context) {
    final displayStyle = Theme.of(context).textTheme.displayLarge?.copyWith(
      fontSize: 58,
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.normal,
      color: AppPalette.green,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _ExpenseHeader(
              title: 'Select Time',
              onClose: () => Navigator.of(context).pop(),
              onConfirm: () => Navigator.of(context).pop(_selectedTime),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: BoxDecoration(
                    color: AppPalette.field,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select time',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.fieldHint,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _mode = _TimeDialMode.hour;
                                    });
                                  },
                                  child: Text(
                                    _hour.toString().padLeft(2, '0'),
                                    style: displayStyle?.copyWith(
                                      color: _mode == _TimeDialMode.hour
                                          ? AppPalette.green
                                          : AppPalette.green.withValues(
                                              alpha: 0.45,
                                            ),
                                    ),
                                  ),
                                ),
                                Text(' : ', style: displayStyle),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _mode = _TimeDialMode.minute;
                                    });
                                  },
                                  child: Text(
                                    _minute.toString().padLeft(2, '0'),
                                    style: displayStyle?.copyWith(
                                      color: _mode == _TimeDialMode.minute
                                          ? AppPalette.green
                                          : AppPalette.green.withValues(
                                              alpha: 0.45,
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              _PeriodButton(
                                label: 'AM',
                                selected: _isAm,
                                onTap: () {
                                  setState(() {
                                    _isAm = true;
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              _PeriodButton(
                                label: 'PM',
                                selected: !_isAm,
                                onTap: () {
                                  setState(() {
                                    _isAm = false;
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Expanded(
                        child: Center(
                          child: _TimeDial(
                            mode: _mode,
                            selectedHour: _hour,
                            selectedMinute: _minute,
                            onHourSelected: (value) {
                              setState(() {
                                _hour = value;
                                _mode = _TimeDialMode.minute;
                              });
                            },
                            onMinuteSelected: (value) {
                              setState(() {
                                _minute = value;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _mode == _TimeDialMode.hour
                            ? 'Tap the clock to select the hour'
                            : 'Tap the clock to select the minutes',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.fieldHint,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
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
                                Navigator.of(context).pop(_selectedTime),
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

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF3D5E7) : const Color(0xFFF8EAF2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppPalette.green : Colors.black12,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
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

class _TimeDial extends StatelessWidget {
  const _TimeDial({
    required this.mode,
    required this.selectedHour,
    required this.selectedMinute,
    required this.onHourSelected,
    required this.onMinuteSelected,
  });

  final _TimeDialMode mode;
  final int selectedHour;
  final int selectedMinute;
  final ValueChanged<int> onHourSelected;
  final ValueChanged<int> onMinuteSelected;

  @override
  Widget build(BuildContext context) {
    final values = mode == _TimeDialMode.hour
        ? List<int>.generate(12, (index) => index + 1)
        : List<int>.generate(12, (index) => index * 5);
    final selectedValue = mode == _TimeDialMode.hour
        ? selectedHour
        : selectedMinute;

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest.shortestSide;
          final radius = size / 2;
          final itemRadius = radius - 26;
          final center = Offset(radius, radius);

          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF8FFFA),
              shape: BoxShape.circle,
            ),
            child: Stack(
              children: [
                for (var index = 0; index < values.length; index++)
                  Builder(
                    builder: (context) {
                      final value = values[index];
                      final angle = ((index + 1 - 3) * 30) * math.pi / 180;
                      final dx = center.dx + itemRadius * math.cos(angle);
                      final dy = center.dy + itemRadius * math.sin(angle);
                      final isSelected = value == selectedValue;

                      return Positioned(
                        left: dx - 18,
                        top: dy - 18,
                        child: GestureDetector(
                          onTap: () {
                            if (mode == _TimeDialMode.hour) {
                              onHourSelected(value);
                              return;
                            }
                            onMinuteSelected(value);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppPalette.green
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              mode == _TimeDialMode.hour
                                  ? '$value'
                                  : value.toString().padLeft(2, '0'),
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppPalette.ink,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                CustomPaint(
                  size: Size.square(size),
                  painter: _DialHandPainter(
                    mode: mode,
                    selectedValue: selectedValue,
                  ),
                ),
                Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppPalette.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DialHandPainter extends CustomPainter {
  const _DialHandPainter({required this.mode, required this.selectedValue});

  final _TimeDialMode mode;
  final int selectedValue;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final step = mode == _TimeDialMode.hour
        ? selectedValue
        : selectedValue ~/ 5;
    final angle = ((step - 3) * 30) * math.pi / 180;
    final handLength = size.width * 0.18;
    final end = Offset(
      center.dx + handLength * math.cos(angle),
      center.dy + handLength * math.sin(angle),
    );

    final paint = Paint()
      ..color = AppPalette.green
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(center, end, paint);
  }

  @override
  bool shouldRepaint(covariant _DialHandPainter oldDelegate) {
    return oldDelegate.selectedValue != selectedValue ||
        oldDelegate.mode != mode;
  }
}
