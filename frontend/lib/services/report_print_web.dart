import 'dart:async';
import 'dart:html' as html;

Future<bool> printReportHtml(String content) async {
  final window = html.window.open('', '_blank');
  if (window == null) return false;
  window.document
    ..open()
    ..write(content)
    ..close();
  await Future<void>.delayed(const Duration(milliseconds: 350));
  window.print();
  return true;
}
