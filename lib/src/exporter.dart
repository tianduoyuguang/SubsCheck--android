import 'dart:convert';
import 'package:flutter/services.dart';

/// 从内核产物 all.yaml（只含 proxies）拼出完整 mihomo 配置。
/// 内核在 sub-store-port 为空时不会生成 mihomo.yaml，所以这里自己拼：
///   mihomo.yaml = proxies 段（来自 all.yaml） + 内置 ACL4SSR 模板（proxy-groups/rule-providers/rules）
class Exporter {
  static String? _templateCache;

  static Future<String> loadTemplate() async {
    final c = _templateCache;
    if (c != null) return c;
    final text = await rootBundle.loadString('assets/ACL4SSR_Online_Full.yaml');
    _templateCache = text;
    return text;
  }

  /// all.yaml 形如：
  /// proxies:
  ///     - name: xxx
  ///       type: ss
  /// 返回 "proxies:" 之后的所有行（保持原缩进，不重新序列化以免丢字段）。
  static String proxiesBlock(String allYaml) {
    final lines = const LineSplitter().convert(allYaml);
    var start = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimRight() == 'proxies:') {
        start = i;
        break;
      }
    }
    if (start < 0) return '';
    final buf = StringBuffer();
    for (var i = start + 1; i < lines.length; i++) {
      final line = lines[i];
      // 顶层结束（出现非缩进行）
      if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t')) break;
      buf.writeln(line);
    }
    return buf.toString();
  }

  static int countProxies(String proxiesBlock) {
    var n = 0;
    for (final line in const LineSplitter().convert(proxiesBlock)) {
      final t = line.trimLeft();
      if (t.startsWith('- ') || t == '-') n++;
    }
    return n;
  }

  /// 完整 mihomo 配置：proxies + 模板
  static Future<String> buildMihomo(String allYaml) async {
    final block = proxiesBlock(allYaml);
    final tpl = await loadTemplate();
    final head = block.trimRight().isEmpty ? 'proxies: []' : 'proxies:\n${block.trimRight()}';
    return '$head\n\n${tpl.trimLeft()}';
  }

  /// 只含节点的精简订阅
  static String buildPlain(String allYaml) {
    final block = proxiesBlock(allYaml);
    if (block.trimRight().isEmpty) return 'proxies: []';
    return 'proxies:\n${block.trimRight()}\n';
  }
}
