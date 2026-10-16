import 'package:PiliPlus/plugin/pl_player/models/hdr_peak_nits.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// 「HDR 视频」设置对话框的返回值：匹配视频亮度开关与峰值亮度。
typedef HdrSettings = ({bool matchVideo, int nits});

/// 「HDR 视频」设置对话框：「匹配视频亮度」开关与「HDR 峰值亮度」滑块、输入框，
/// 滑块按 [HdrPeakNits.step] 粗调、输入框填精确值，两者保持同步。
/// 确定时返回新的取值，取消返回 null。
class HdrSettingsDialog extends StatefulWidget {
  const HdrSettingsDialog({
    super.key,
    required this.matchVideo,
    required this.value,
  });

  /// 开启「匹配视频亮度」时 [value] 不生效，说明文字随之不同。
  final bool matchVideo;

  final int value;

  @override
  State<HdrSettingsDialog> createState() => _HdrSettingsDialogState();
}

class _HdrSettingsDialogState extends State<HdrSettingsDialog> {
  late bool _matchVideo = widget.matchVideo;
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
    Navigator.pop(context, (matchVideo: _matchVideo, nits: value));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('HDR 视频'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('匹配视频亮度'),
              value: _matchVideo,
              onChanged: (value) => setState(() => _matchVideo = value),
            ),
            Text(
              _matchVideo
                  ? '已开启匹配视频亮度，按片源亮度输出，峰值亮度设置不生效（可能超出屏幕最高亮度）'
                  : '过高峰值亮度的视频映射进这个范围，不被屏幕截断；'
                        '合理填写避免画面过曝/过暗',
              style: theme.textTheme.labelMedium!.copyWith(
                color: theme.colorScheme.outline,
              ),
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
                labelText: 'HDR 峰值亮度',
                suffixText: 'nit',
                helperText:
                    '${HdrPeakNits.min}–${HdrPeakNits.max}，默认 ${HdrPeakNits.defaultValue}',
              ),
              onChanged: _onType,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(
            '取消',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),
        TextButton(onPressed: _confirm, child: const Text('确定')),
      ],
    );
  }
}
