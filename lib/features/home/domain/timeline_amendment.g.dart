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
      slot1State: fields[13] as String?,
      slot2State: fields[14] as String?,
      slot3State: fields[15] as String?,
      slot4State: fields[16] as String?,
      slot5State: fields[17] as String?,
      slot6State: fields[18] as String?,
      slot7State: fields[19] as String?,
      slot8State: fields[20] as String?,
      slot9State: fields[21] as String?,
      slot10State: fields[22] as String?,
      slot11State: fields[23] as String?,
      slot12State: fields[24] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, TimelineAmendment obj) {
    writer
      ..writeByte(21)
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
      ..writeByte(13)
      ..write(obj.slot1State)
      ..writeByte(14)
      ..write(obj.slot2State)
      ..writeByte(15)
      ..write(obj.slot3State)
      ..writeByte(16)
      ..write(obj.slot4State)
      ..writeByte(17)
      ..write(obj.slot5State)
      ..writeByte(18)
      ..write(obj.slot6State)
      ..writeByte(19)
      ..write(obj.slot7State)
      ..writeByte(20)
      ..write(obj.slot8State)
      ..writeByte(21)
      ..write(obj.slot9State)
      ..writeByte(22)
      ..write(obj.slot10State)
      ..writeByte(23)
      ..write(obj.slot11State)
      ..writeByte(24)
      ..write(obj.slot12State);
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
