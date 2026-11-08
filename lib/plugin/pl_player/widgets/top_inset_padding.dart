import 'package:material_ui/material_ui.dart';

/// 顶部避让内边距：竖屏全屏时弹幕、播控顶部组件共用的统一 Padding。
/// [inset] 为 null 或 <= 0 时不加内边距，原样返回 child。
class TopInsetPadding extends StatelessWidget {
  const TopInsetPadding({super.key, required this.inset, required this.child});

  final double? inset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = inset ?? 0;
    return top > 0
        ? Padding(padding: EdgeInsets.only(top: top), child: child)
        : child;
  }
}
