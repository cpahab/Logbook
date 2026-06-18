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
      motorOn: fields[13] as bool?,
      grossState: fields[14] as String?,
      fockState: fields[15] as String?,
      vesselStatusNote: fields[16] as String?,
      keelDown: fields[17] as bool?,
    );
  }

  @override
  void write(BinaryWriter writer, TimelineEntry obj) {
    writer
      ..writeByte(12)
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
      ..writeByte(13)
      ..write(obj.motorOn)
      ..writeByte(14)
      ..write(obj.grossState)
      ..writeByte(15)
      ..write(obj.fockState)
      ..writeByte(16)
      ..write(obj.vesselStatusNote)
      ..writeByte(17)
      ..write(obj.keelDown);
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
