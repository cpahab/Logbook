import 'package:flutter/material.dart';
import '../domain/timeline_entry.dart';

class AddTimelineEntryDialog extends StatefulWidget {
  final DateTime day;
  const AddTimelineEntryDialog({super.key, required this.day});

  @override
  State<AddTimelineEntryDialog> createState() => _AddTimelineEntryDialogState();
}

class _AddTimelineEntryDialogState extends State<AddTimelineEntryDialog> {
  TimeOfDay selectedTime = TimeOfDay.now();

  final courseCtrl = TextEditingController();
  final speedCtrl = TextEditingController();
  final windCtrl = TextEditingController();
  final seaCtrl = TextEditingController();
  final weatherCtrl = TextEditingController();
  final remarksCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Add Timeline Entry"),
      content: SingleChildScrollView(
        child: Column(
          children: [
            // TIME PICKER
            Row(
              children: [
                const Text("Time: "),
                TextButton(
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
                    if (t != null) setState(() => selectedTime = t);
                  },
                  child: Text(selectedTime.format(context)),
                ),
              ],
            ),

            TextField(
              controller: courseCtrl,
              decoration: const InputDecoration(labelText: "Course (°)"),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: speedCtrl,
              decoration: const InputDecoration(labelText: "Speed (kn)"),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: windCtrl,
              decoration: const InputDecoration(labelText: "Wind"),
            ),
            TextField(
              controller: seaCtrl,
              decoration: const InputDecoration(labelText: "Sea"),
            ),
            TextField(
              controller: weatherCtrl,
              decoration: const InputDecoration(labelText: "Weather"),
            ),
            TextField(
              controller: remarksCtrl,
              decoration: const InputDecoration(labelText: "Remarks"),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () {
            final now = DateTime.now();
            final dt = DateTime(
              widget.day.year,
              widget.day.month,
              widget.day.day,
              selectedTime.hour,
              selectedTime.minute,
            );

            final entry = TimelineEntry(
              time: dt,
              course: _parseDouble(courseCtrl.text),
              speed: _parseDouble(speedCtrl.text),
              wind: windCtrl.text.isEmpty ? null : windCtrl.text,
              sea: seaCtrl.text.isEmpty ? null : seaCtrl.text,
              weather: weatherCtrl.text.isEmpty ? null : weatherCtrl.text,
              remarks: remarksCtrl.text.isEmpty ? null : remarksCtrl.text,
            );

            Navigator.pop(context, entry);
          },
          child: const Text("Add"),
        ),
      ],
    );
  }

  double? _parseDouble(String s) {
    if (s.trim().isEmpty) return null;
    return double.tryParse(s.replaceAll(",", "."));
  }
}
