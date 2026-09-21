import 'package:JsxposedX/features/apk_analysis/domain/repositories/apk_analysis_query_repository.dart';
import 'package:JsxposedX/features/so_analysis/data/datasources/so_analysis_datasource.dart';

/// APK 逆向工具运行时上下文。
///
/// 由环境装配方（[ApkReverseAiEnvironment] / 环境适配器）在会话初始化时构建，
/// 传递给全部注册工具的 handler 工厂（见 [AiToolRegistry]）。
class ApkReverseToolRuntimeContext {
  const ApkReverseToolRuntimeContext({
    required this.repo,
    required this.soDataSource,
    required this.sessionId,
    required this.dexPaths,
    this.packageName = '',
    this.isZh = true,
  });

  final ApkAnalysisQueryRepository repo;
  final SoAnalysisDatasource soDataSource;
  final String sessionId;
  final List<String> dexPaths;

  /// 当前分析的目标包名（阶段1 起供脚本保存/开关类工具使用）
  final String packageName;

  /// 会话语言（工具结果文案本地化）
  final bool isZh;
}
