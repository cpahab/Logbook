// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'crew_member.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CrewMemberAdapter extends TypeAdapter<CrewMember> {
  @override
  final int typeId = 12;

  @override
  CrewMember read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CrewMember(
      name: fields[0] as String,
      bloodType: fields[1] as String?,
      allergies: fields[2] as String?,
      conditions: fields[3] as String?,
      remarks: fields[4] as String?,
      id: fields[5] as String?,
      personalEpirb: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, CrewMember obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.bloodType)
      ..writeByte(2)
      ..write(obj.allergies)
      ..writeByte(3)
      ..write(obj.conditions)
      ..writeByte(4)
      ..write(obj.remarks)
      ..writeByte(5)
      ..write(obj.id)
      ..writeByte(6)
      ..write(obj.personalEpirb);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CrewMemberAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
