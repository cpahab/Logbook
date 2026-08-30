import 'dart:convert';

/// One configurable equipment slot on the vessel (e.g. "Grosssegel").
/// Up to [maxStates] state labels can be defined (e.g. "Voll", "1. Reff").
class EquipmentSlot {
  static const maxStates = 5;

  final String key;    // fixed storage key: 'slot1' … 'slot12'
  final String label;  // user-defined name shown above the chips
  final List<String> states; // ordered list of state labels (max 5)

  const EquipmentSlot({
    required this.key,
    required this.label,
    required this.states,
  });

  bool get isEmpty => label.trim().isEmpty || states.isEmpty;

  EquipmentSlot copyWith({String? label, List<String>? states}) =>
      EquipmentSlot(key: key, label: label ?? this.label, states: states ?? this.states);

  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'states': states};

  factory EquipmentSlot.fromJson(Map<String, dynamic> j) => EquipmentSlot(
        key: j['key'] as String,
        label: j['label'] as String,
        states: List<String>.from(j['states'] as List),
      );

  static EquipmentSlot empty(String key) =>
      EquipmentSlot(key: key, label: '', states: const []);
}

/// The full set of 12 equipment slots for one vessel.
/// Slots 1–10 are for sails; slot11 is the motor/engine; slot12 is the keel.
/// Empty slots (no label or no states) are hidden in the dialog.
/// Stored as JSON in the synced settings doc; loaded on app start.
class VesselEquipmentConfig {
  /// Fixed slot keys, always in this order.
  static const slotKeys = [
    'slot1', 'slot2', 'slot3', 'slot4', 'slot5',
    'slot6', 'slot7', 'slot8', 'slot9', 'slot10',
    'slot11', 'slot12',
  ];

  final List<EquipmentSlot> slots; // always exactly 12

  const VesselEquipmentConfig(this.slots) : assert(slots.length == 12);

  /// Active (non-empty) slots — these appear in the timeline entry dialog.
  List<EquipmentSlot> get activeSlots => slots.where((s) => !s.isEmpty).toList();

  /// Default config for a new vessel, seeded from the app's previous
  /// hardwired main/jib/motor/keel chip rows so behaviour is unchanged for
  /// anyone who hasn't customised their equipment yet. Mirrors whichever
  /// language ([languageCode]) those chips used to render in — 'de' or 'en'.
  factory VesselEquipmentConfig.defaultForLocale(String languageCode) {
    final de = languageCode != 'en';
    return VesselEquipmentConfig([
      EquipmentSlot(
        key: 'slot1',
        label: de ? 'Gross' : 'Main',
        states: de
            ? const ['Voll gesetzt', '1. Reff', '2. Reff', 'Niedergeholt']
            : const ['Full sail', '1st reef', '2nd reef', 'Lowered'],
      ),
      EquipmentSlot(
        key: 'slot2',
        label: de ? 'Fock' : 'Jib',
        states: de
            ? const ['Voll gesetzt', '1. Reff', '2. Reff', 'Eingerollt']
            : const ['Full sail', '1st reef', '2nd reef', 'Furled'],
      ),
      EquipmentSlot.empty('slot3'),
      EquipmentSlot.empty('slot4'),
      EquipmentSlot.empty('slot5'),
      EquipmentSlot.empty('slot6'),
      EquipmentSlot.empty('slot7'),
      EquipmentSlot.empty('slot8'),
      EquipmentSlot.empty('slot9'),
      EquipmentSlot.empty('slot10'),
      EquipmentSlot(
        key: 'slot11',
        label: de ? 'Motor' : 'Engine',
        states: de ? const ['An', 'Aus'] : const ['On', 'Off'],
      ),
      EquipmentSlot(
        key: 'slot12',
        label: de ? 'Kiel' : 'Keel',
        states: de ? const ['Unten', 'Oben'] : const ['Down', 'Up'],
      ),
    ]);
  }

  VesselEquipmentConfig copyWithSlot(EquipmentSlot updated) => VesselEquipmentConfig(
        slots.map((s) => s.key == updated.key ? updated : s).toList(),
      );

  /// Maps a recorded slot12 (keel) state label back to true (down) / false
  /// (up), using its position in the keel slot's configured state list —
  /// index 0 is always "down", index 1 is always "up", the fixed convention
  /// set by [defaultForLocale] and preserved even if a user renames the
  /// labels. Returns null if [state] is null or doesn't match either
  /// position (e.g. the keel slot was cleared or reconfigured since).
  bool? keelDownFor(String? state) {
    if (state == null) return null;
    final keel = slots.firstWhere(
      (s) => s.key == 'slot12',
      orElse: () => EquipmentSlot.empty('slot12'),
    );
    final idx = keel.states.indexOf(state);
    if (idx == 0) return true;
    if (idx == 1) return false;
    return null;
  }

  String toJsonString() =>
      jsonEncode({'slots': slots.map((s) => s.toJson()).toList()});

  factory VesselEquipmentConfig.fromJsonString(String raw, {String languageCode = 'de'}) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = (data['slots'] as List)
          .map((e) => EquipmentSlot.fromJson(e as Map<String, dynamic>))
          .toList();
      // Ensure exactly 12 slots keyed slot1…slot12; fill any missing with empty.
      final map = {for (final s in list) s.key: s};
      return VesselEquipmentConfig(
        VesselEquipmentConfig.slotKeys
            .map((k) => map[k] ?? EquipmentSlot.empty(k))
            .toList(),
      );
    } catch (_) {
      return VesselEquipmentConfig.defaultForLocale(languageCode);
    }
  }
}
