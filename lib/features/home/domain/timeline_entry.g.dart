// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TimelineEntryAdapter extends TypeAdapter<TimelineEntry> {
  @override
  final int typeId = 2;

  @override
  TimelineEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TimelineEntry(
      time: fields[0] as DateTime,
      course: fields[1] as double?,
      speed: fields[2] as double?,
      wind: fields[3] as String?,
      sea: fields[4] as String?,
      weather: fields[5] as String?,
      remarks: fields[6] as String?,
      vesselStatusNote: fields[16] as String?,
      createdAt: fields[18] as DateTime?,
      updatedAt: fields[19] as DateTime?,
      amendments: (fields[20] as List?)?.cast<TimelineAmendment>(),
      slot1State: fields[21] as String?,
      slot2State: fields[22] as String?,
      slot3State: fields[23] as String?,
      slot4State: fields[24] as String?,
      slot5State: fields[25] as String?,
      slot6State: fields[26] as String?,
      slot7State: fields[27] as String?,
      slot8State: fields[28] as String?,
      slot9State: fields[29] as String?,
      slot10State: fields[30] as String?,
      slot11State: fields[31] as String?,
      slot12State: fields[32] as String?,
      temperature: fields[33] as double?,
      pressure: fields[34] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, TimelineEntry obj) {
    writer
      ..writeByte(25)
      ..writeByte(0)
      ..write(obj.time)
      ..writeByte(1)
      ..write(obj.course)
      ..writeByte(2)
      ..write(obj.speed)
      ..writeByte(3)
      ..write(obj.wind)
      ..writeByte(4)
      ..write(obj.sea)
      ..writeByte(5)
      ..write(obj.weather)
      ..writeByte(6)
      ..write(obj.remarks)
      ..writeByte(16)
      ..write(obj.vesselStatusNote)
      ..writeByte(18)
      ..write(obj.createdAt)
      ..writeByte(19)
      ..write(obj.updatedAt)
      ..writeByte(20)
      ..write(obj.amendments)
      ..writeByte(21)
      ..write(obj.slot1State)
      ..writeByte(22)
      ..write(obj.slot2State)
      ..writeByte(23)
      ..write(obj.slot3State)
      ..writeByte(24)
      ..write(obj.slot4State)
      ..writeByte(25)
      ..write(obj.slot5State)
      ..writeByte(26)
      ..write(obj.slot6State)
      ..writeByte(27)
      ..write(obj.slot7State)
      ..writeByte(28)
      ..write(obj.slot8State)
      ..writeByte(29)
      ..write(obj.slot9State)
      ..writeByte(30)
      ..write(obj.slot10State)
      ..writeByte(31)
      ..write(obj.slot11State)
      ..writeByte(32)
      ..write(obj.slot12State)
      ..writeByte(33)
      ..write(obj.temperature)
      ..writeByte(34)
      ..write(obj.pressure);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
