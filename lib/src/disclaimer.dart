import 'package:flutter/material.dart';

/// 免责声明正文。设置页条目和启动时的首次提示共用同一份文案。
const String kDisclaimer = '''
一、软件性质
本应用（SubsCheck for Android）是开源软件 SubsCheck 的安卓移植版，仅供学习、研究与个人网络调试使用。软件按「现状」（AS IS）提供，不附带任何明示或默示的担保，包括但不限于可用性、稳定性、适销性与特定用途适用性。

二、使用风险
1. 本应用只负责对您自行提供的订阅链接做连通性、延迟与出口信息的检测，并把结果整理成配置文件，本身不提供任何网络接入服务，也不内置、分发或代理任何节点。
2. 您需要自行确保所使用订阅来源的合法性，以及使用行为符合所在地法律法规与网络服务提供商的服务条款。因使用本软件产生的一切后果由使用者自行承担。
3. 检测过程会向第三方站点发起大量并发请求，可能触发对方的风控或限流；请勿在未经授权的网络环境中使用。
4. 节点测速、媒体解锁检测结果受运营商、时段、设备性能影响，仅供参考，不构成对任何服务质量或可用性的承诺。

三、数据与隐私
1. 所有配置、订阅链接、检测结果和导出文件均保存在本机应用私有目录，不会上传到开发者服务器。
2. 「检查更新」会请求 GitHub 公开的 release 接口，仅交换版本号信息；该请求受 GitHub 隐私政策约束。
3. 内核在检测过程中会以节点身份访问第三方站点，这些站点可能记录您的出口 IP，属于检测行为本身不可避免的部分。

四、责任限制
在适用法律允许的最大范围内，开发者与贡献者不对因使用或无法使用本软件而导致的任何直接、间接、附带、特殊或后果性损害承担责任，包括但不限于利润损失、数据丢失、业务中断。

五、开源许可
本应用及其内置内核（beck-8/subs-check）均以 GNU General Public License v3 发布。您可以自由使用、修改和再分发，但再分发时须同样以 GPLv3 开放源代码，并保留原始版权声明。

继续使用即表示您已阅读、理解并同意上述全部条款。若不同意，请立即停止使用并卸载本应用。
''';

/// 可滚动的免责声明对话框。
Future<void> showDisclaimerDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('免责声明'),
      content: SizedBox(
        width: double.maxFinite,
        height: 460,
        child: SingleChildScrollView(
          child: SelectableText(
            kDisclaimer.trim(),
            style: const TextStyle(fontSize: 12.5, height: 1.55),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
      ],
    ),
  );
}
