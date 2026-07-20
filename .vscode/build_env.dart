import 'dart:convert';
import 'dart:io';

Future<void> _updatePubspecVersion(int versionCode) async {
  final pubspecPath = './pubspec.yaml';
  final file = File(pubspecPath);
  if (!await file.exists()) return;
  
  final content = await file.readAsString();
  final lines = content.split('\n');
  
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('version:')) {
      final match = RegExp(r'version:\s*([\d.]+)(\+[\d]+)?').firstMatch(lines[i]);
      if (match != null) {
        final versionName = match.group(1)!;
        lines[i] = 'version: $versionName+$versionCode';
        await file.writeAsString(lines.join('\n'));
        break;
      }
    }
  }
}

void main() async {
  // 手动指定 versionName
  const versionName = '2.0.1-ohos-3';

  // 通过 git 命令获取 hash 和 code
  final versionCode = await _getGitCommitCount();
  final commitHash = await _getGitCommitHash();
  
  await _updatePubspecVersion(versionCode);

  final env = {
    '此环境变量由脚本自动生成': '请勿编辑',
    'pili.name': versionName,
    // 别问为什么除以1000，因为解码那边不知道为什么乘了1000
    'pili.time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'pili.hash': commitHash,
    'pili.code': versionCode,
    'ENABLE_FLEX_OVERFLOW': false
  };
  File('./.vscode/env.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(env));
}

// 获取 Git 提交数量作为版本号
Future<int> _getGitCommitCount() async {
  try {
    final result = await Process.run('git', ['rev-list', '--count', 'HEAD']);
    if (result.exitCode == 0) {
      return int.tryParse(result.stdout.toString().trim()) ?? 0;
    }
  } catch (e) {
    print('获取 Git 提交数量失败: $e');
  }
  return 0;
}

// 获取 Git 提交哈希值
Future<String> _getGitCommitHash() async {
  try {
    final result = await Process.run('git', ['rev-parse', 'HEAD']);
    if (result.exitCode == 0) {
      return result.stdout.toString().trim();
    }
  } catch (e) {
    print('获取 Git 提交哈希值失败: $e');
  }
  return '';
}
