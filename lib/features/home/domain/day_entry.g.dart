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
      fromHarbor: fields[4] as String?,
      toHarbor: fields[5] as String?,
      distanceNm: fields[6] as double,
      totalDurationSeconds: fields[7] as int,
      movingDurationSeconds: fields[8] as int,
      avgSpeedKnots: fields[9] as double,
      maxSpeedKnots: fields[10] as double,
      participantsList: (fields[13] as List?)?.cast<String>(),
      notes: fields[15] as String?,
      oilLevel: fields[16] as int?,
      fuelLevel: fields[17] as int?,
      crew: (fields[18] as List?)?.cast<CrewMember>(),
      freeText: fields[19] as String?,
      keelDown: fields[20] as bool?,
      photos: (fields[21] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, DayEntry obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.timeline)
      ..writeByte(2)
      ..write(obj.track)
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
      ..write(obj.maxSpeedKnots)
      ..writeByte(13)
      ..write(obj.participantsList)
      ..writeByte(15)
      ..write(obj.notes)
      ..writeByte(16)
      ..write(obj.oilLevel)
      ..writeByte(17)
      ..write(obj.fuelLevel)
      ..writeByte(18)
      ..write(obj.crew)
      ..writeByte(19)
      ..write(obj.freeText)
      ..writeByte(20)
      ..write(obj.keelDown)
      ..writeByte(21)
      ..write(obj.photos);
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
