import 'package:PiliPlus/plugin/pl_player/models/hdr_peak_nits.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// 「HDR 峰值亮度」设置对话框：滑块按 [HdrPeakNits.step] 粗调，输入框填精确值，
/// 两者保持同步。确定时返回新的 nit 值，取消返回 null。
class HdrPeakNitsDialog extends StatefulWidget {
  const HdrPeakNitsDialog({
    super.key,
    required this.value,
    required this.matchVideo,
  });

  final int value;

  /// 开启「匹配视频亮度」时这里的值不生效，说明文字随之不同。
  final bool matchVideo;

  @override
  State<HdrPeakNitsDialog> createState() => _HdrPeakNitsDialogState();
}

class _HdrPeakNitsDialogState extends State<HdrPeakNitsDialog> {
  late int _value = widget.value;
  late final _input = TextEditingController(text: '${widget.value}');

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _onSlide(double position) {
    final value = HdrPeakNits.snap(position);
    setState(() => _value = value);
    _input.text = '$value';
  }

  void _onType(String text) {
    final value = HdrPeakNits.tryParse(text);
    if (value != null) {
      setState(() => _value = value);
    }
  }

  void _confirm() {
    final value = HdrPeakNits.tryParse(_input.text);
    if (value == null) {
      SmartDialog.showToast(
        '请输入 ${HdrPeakNits.min}–${HdrPeakNits.max} 之间的整数',
      );
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('HDR 峰值亮度'),
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          Text(
            widget.matchVideo
                ? '已开启「匹配视频亮度」：HDR 画面保持片源亮度，不随系统亮度变化，'
                      '这里的值不生效，关闭后才按它做色调映射。'
                : '片源的峰值映射到这里：比它亮的高光由播放器压缩进这个范围，'
                      '而不是被屏幕截断。按屏幕的峰值亮度填写；填得比屏幕能达到'
                      '的还高时，超出的部分仍会被屏幕截断。',
          ),
          const SizedBox(height: 12),
          Slider(
            value: _value.toDouble(),
            min: HdrPeakNits.min.toDouble(),
            max: HdrPeakNits.max.toDouble(),
            divisions: (HdrPeakNits.max - HdrPeakNits.min) ~/ HdrPeakNits.step,
            label: '$_value nit',
            onChanged: _onSlide,
          ),
          TextField(
            controller: _input,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              suffixText: 'nit',
              helperText:
                  '${HdrPeakNits.min}–${HdrPeakNits.max}，默认 ${HdrPeakNits.defaultValue}',
            ),
            onChanged: _onType,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(onPressed: _confirm, child: const Text('确定')),
      ],
    );
  }
}
