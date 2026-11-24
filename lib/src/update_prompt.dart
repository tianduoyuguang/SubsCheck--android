import 'package:flutter/material.dart';

/// 启动时自动检查更新的选择结果。
///
/// 用 String 而不是 enum，纯粹是为了让调用方少 import 一个类型；
/// 取值只可能是这三个常量之一。
class UpdateChoice {
  static const String update = 'update';
  static const String later = 'later';
  static const String skip = 'skip';
}

/// 启动时发现新版本的提示框。
///
/// 三个出口分别对应「现在就去更新」「这次先不更新」「以后别再提示这个版本」。
/// 返回 [UpdateChoice] 里的常量；用户按返回键/点遮罩关闭时按 [UpdateChoice.later] 处理。
Future<String> showUpdatePrompt(
  BuildContext context, {
  required String currentVersion,
  required String latestVersion,
  String? notes,
}) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('发现新版本'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('当前 v$currentVersion  ·  最新 v$latestVersion'),
            if (notes != null && notes.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Flexible(
                child: Container(
                  width: double.maxFinite,
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      notes.trim(),
                      style: const TextStyle(fontSize: 12, height: 1.45),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '选择「不再提示此版本」后，只有出现更新的版本才会再次提醒。',
              style: TextStyle(fontSize: 11.5, color: Theme.of(ctx).colorScheme.outline),
            ),
          ],
        ),
      ),
      actionsOverflowButtonSpacing: 8,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx, UpdateChoice.skip),
          child: const Text('不再提示'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, UpdateChoice.later),
          child: const Text('以后再说'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, UpdateChoice.update),
          child: const Text('立即更新'),
        ),
      ],
    ),
  );
  return choice ?? UpdateChoice.later;
}
