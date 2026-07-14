/// Formats decimal-degree [lat]/[lng] as nautical degrees-minutes-decimal:
/// "N 47° 30.456'  E 008° 18.123'".
String formatDDM(double lat, double lng) {
  String ddm(double val, List<String> dirs) {
    final dir = val >= 0 ? dirs[0] : dirs[1];
    final abs = val.abs();
    final deg = abs.truncate();
    final min = (abs - deg) * 60;
    return "$dir ${deg.toString().padLeft(dirs[0] == 'N' ? 2 : 3, '0')}° ${min.toStringAsFixed(3)}'";
  }
  return '${ddm(lat, ['N', 'S'])}  ${ddm(lng, ['E', 'W'])}';
}
