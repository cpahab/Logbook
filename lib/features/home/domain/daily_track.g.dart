// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_track.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DailyTrackAdapter extends TypeAdapter<DailyTrack> {
  @override
  final int typeId = 3;

  @override
  DailyTrack read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DailyTrack(
      day: fields[0] as DateTime,
      fileName: fields[1] as String,
      points: (fields[2] as List).cast<TrackPoint>(),
    );
  }

  @override
  void write(BinaryWriter writer, DailyTrack obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.day)
      ..writeByte(1)
      ..write(obj.fileName)
      ..writeByte(2)
      ..write(obj.points);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyTrackAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
