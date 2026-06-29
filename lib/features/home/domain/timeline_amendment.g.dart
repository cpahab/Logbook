// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_amendment.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TimelineAmendmentAdapter extends TypeAdapter<TimelineAmendment> {
  @override
  final int typeId = 14;

  @override
  TimelineAmendment read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TimelineAmendment(
      amendedAt: fields[0] as DateTime,
      reason: fields[1] as String?,
      time: fields[2] as DateTime,
      course: fields[3] as double?,
      speed: fields[4] as double?,
      wind: fields[5] as String?,
      sea: fields[6] as String?,
      weather: fields[7] as String?,
      remarks: fields[8] as String?,
      grossState: fields[9] as String?,
      fockState: fields[10] as String?,
      motorOn: fields[11] as bool?,
      keelDown: fields[12] as bool?,
    );
  }

  @override
  void write(BinaryWriter writer, TimelineAmendment obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.amendedAt)
      ..writeByte(1)
      ..write(obj.reason)
      ..writeByte(2)
      ..write(obj.time)
      ..writeByte(3)
      ..write(obj.course)
      ..writeByte(4)
      ..write(obj.speed)
      ..writeByte(5)
      ..write(obj.wind)
      ..writeByte(6)
      ..write(obj.sea)
      ..writeByte(7)
      ..write(obj.weather)
      ..writeByte(8)
      ..write(obj.remarks)
      ..writeByte(9)
      ..write(obj.grossState)
      ..writeByte(10)
      ..write(obj.fockState)
      ..writeByte(11)
      ..write(obj.motorOn)
      ..writeByte(12)
      ..write(obj.keelDown);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineAmendmentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
