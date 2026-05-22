// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'day_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DayEntryAdapter extends TypeAdapter<DayEntry> {
  @override
  final int typeId = 11;

  @override
  DayEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DayEntry(
      date: fields[0] as DateTime,
      timeline: (fields[1] as List).cast<TimelineEntry>(),
      track: (fields[2] as List).cast<TrackPoint>(),
      hasGpx: fields[3] as bool,
      fromHarbor: fields[4] as String?,
      toHarbor: fields[5] as String?,
      distanceNm: fields[6] as double,
      totalDurationSeconds: fields[7] as int,
      movingDurationSeconds: fields[8] as int,
      avgSpeedKnots: fields[9] as double,
      maxSpeedKnots: fields[10] as double,
    );
  }

  @override
  void write(BinaryWriter writer, DayEntry obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.timeline)
      ..writeByte(2)
      ..write(obj.track)
      ..writeByte(3)
      ..write(obj.hasGpx)
      ..writeByte(4)
      ..write(obj.fromHarbor)
      ..writeByte(5)
      ..write(obj.toHarbor)
      ..writeByte(6)
      ..write(obj.distanceNm)
      ..writeByte(7)
      ..write(obj.totalDurationSeconds)
      ..writeByte(8)
      ..write(obj.movingDurationSeconds)
      ..writeByte(9)
      ..write(obj.avgSpeedKnots)
      ..writeByte(10)
      ..write(obj.maxSpeedKnots);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
