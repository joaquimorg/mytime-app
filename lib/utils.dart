import 'dart:typed_data';

List<int> buildHeader(int cmd, List<int> payload) {
  BytesBuilder notification = BytesBuilder();

  int plLenght = payload.length;

  //var bdata = ByteData(2);
  //bdata.setInt16(0, payload.length);

  notification.addByte(0);
  notification.addByte(cmd);
  notification.addByte((plLenght & 255));
  notification.addByte((plLenght >> 8) & 255);
  notification.add(payload);
  return notification.toBytes();
}

List<int> intToList(int value) {
  BytesBuilder notification = BytesBuilder();
  var bdata = ByteData(4);
  bdata.setInt32(0, value);

  notification.add(bdata.buffer.asUint8List());
  return notification.toBytes();
}

String truncateWithEllipsis(int cutoff, String myString) {
  return (myString.length <= cutoff)
      ? myString
      : '${myString.substring(0, cutoff - 3)}...';
}
