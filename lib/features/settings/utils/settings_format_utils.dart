/// Formats an 8-char share code as "XXXX-XXXX" for display.
String formatCode(String code) {
  if (code.length == 8) return '${code.substring(0, 4)}-${code.substring(4)}';
  return code;
}
