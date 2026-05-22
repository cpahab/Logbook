// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'track_point.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TrackPointAdapter extends TypeAdapter<TrackPoint> {
  @override
  final int typeId = 4;

  @override
  TrackPoint read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TrackPoint(
      lat: fields[0] as double,
      lon: fields[1] as double,
      time: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, TrackPoint obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.lat)
      ..writeByte(1)
      ..write(obj.lon)
      ..writeByte(2)
      ..write(obj.time);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackPointAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
