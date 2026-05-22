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
    );
  }

  @override
  void write(BinaryWriter writer, TimelineEntry obj) {
    writer
      ..writeByte(7)
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
      ..write(obj.remarks);
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
