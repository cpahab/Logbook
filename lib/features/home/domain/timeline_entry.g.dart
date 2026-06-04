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
      fockUp: fields[7] as bool?,
      grossUp: fields[8] as bool?,
      reff1Fock: fields[9] as bool?,
      reff1Gross: fields[10] as bool?,
      reff2Fock: fields[11] as bool?,
      reff2Gross: fields[12] as bool?,
      motorOn: fields[13] as bool?,
      grossState: fields[14] as String?,
      fockState: fields[15] as String?,
      vesselStatusNote: fields[16] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, TimelineEntry obj) {
    writer
      ..writeByte(17)
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
      ..writeByte(7)
      ..write(obj.fockUp)
      ..writeByte(8)
      ..write(obj.grossUp)
      ..writeByte(9)
      ..write(obj.reff1Fock)
      ..writeByte(10)
      ..write(obj.reff1Gross)
      ..writeByte(11)
      ..write(obj.reff2Fock)
      ..writeByte(12)
      ..write(obj.reff2Gross)
      ..writeByte(13)
      ..write(obj.motorOn)
      ..writeByte(14)
      ..write(obj.grossState)
      ..writeByte(15)
      ..write(obj.fockState)
      ..writeByte(16)
      ..write(obj.vesselStatusNote);
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
