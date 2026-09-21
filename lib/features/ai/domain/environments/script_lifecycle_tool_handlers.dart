import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_tool_handler.dart';
import 'package:JsxposedX/features/ai/domain/environments/ai_tool_runtime_context.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';
import 'package:JsxposedX/generated/pinia.g.dart';
import 'package:JsxposedX/generated/project.g.dart';

// ═══ Xposed Hook 模板常量（对齐 JsSugar.kt 链式 API） ═══

const _xposedHookBeforeAfter = r'''
Jx.use("{className}")
  .hook("{methodName}", [{paramList}], {{
    before: function(self, ...args) {{
      console.log("[Hook] {methodName} 调用前");
      console.log("参数:", args);
      // TODO: 修改参数：args[0] = newValue;
    }},
    after: function(self, result, ...args) {{
      console.log("[Hook] {methodName} 返回:", result);
      // TODO: 修改返回值：result = newValue;
    }}
  }});
''';

const _xposedHookBefore = r'''
Jx.use("{className}")
  .hook("{methodName}", [{paramList}], {{
    before: function(self, ...args) {{
      console.log("[Hook] {methodName} 调用前");
      console.log("参数:", args);
      // TODO: 在方法执行前注入逻辑
    }}
  }});
''';

const _xposedHookAfter = r'''
Jx.use("{className}")
  .hook("{methodName}", [{paramList}], {{
    after: function(self, result, ...args) {{
      console.log("[Hook] {methodName} 返回:", result);
      console.log("参数:", args);
      // TODO: 修改返回值：return newResult;
    }}
  }});
''';

const _xposedHookReplace = r'''
Jx.use("{className}")
  .hook("{methodName}", [{paramList}], {{
    replace: function(self, ...args) {{
      console.log("[Hook] {methodName} 被替换");
      console.log("参数:", args);
      // TODO: 自定义逻辑
      return original(self, ...args); // 或返回自定义值
    }}
  }});
''';

const _xposedMethodEnumTemplate = r'''
// {className} 的方法列表：
// {methodList}
//
// 以下为每个方法生成的 Hook 骨架：
{methodSkeletons}
''';

const _xposedMethodSkeleton = r'''
// --- {methodName}({paramTypes}) ---
Jx.use("{className}")
  .hook("{methodName}", [{paramListStr}], {{
    before: function(self, ...args) {{
      console.log("[Hook] {className}.{methodName} 调用");
      // TODO: 添加业务逻辑
    }}
  }});
''';

// ═══ Frida Hook 模板常量（对齐 FridaSugar.kt 的 Fx API） ═══

const _fridaJavaMethod = r'''
// Fx 糖 Java 方法 Hook
Fx.use("{className}")
  .{methodName}
  .overload({overloadArgs})
  .implementation = function({paramList}) {{
    console.log("[Fx] {className}.{methodName} 调用");
    console.log("参数:", arguments);
    // TODO: 添加业务逻辑
    return this.{methodName}({paramList}); // 调用原方法
  }};
''';

const _fridaJniSymbol = r'''
// Fx 糖 JNI 原生符号 Hook
Fx.hookNative("{soName}", "{symbolName}", {{
  onEnter: function(args) {{
    console.log("[Fx] {symbolName} 进入");
    console.log("参数:", args);
    // TODO: 处理参数
  }},
  onLeave: function(retval) {{
    console.log("[Fx] {symbolName} 返回:", retval);
    // TODO: 处理返回值
  }}
}});
''';

const _fridaAddress = r'''
// Fx 糖地址 Hook（{address}）
const module = Process.getModuleByName("{soName}");
const targetAddr = module.base.add({offset});
Interceptor.attach(targetAddr, {{
  onEnter: function(args) {{
    console.log("[Fx] 地址 Hook 进入: {address}");
    console.log("参数:", args);
    // TODO: 业务逻辑
  }},
  onLeave: function(retval) {{
    console.log("[Fx] 地址 Hook 返回:", retval);
  }}
}});
''';

// ═══ Handler 基类 ═══

/// 脚本生命周期工具 handler 基类。
///
/// 使用 [ApkReverseToolRuntimeContext] 获取 packageName/isZh，
/// 通过 Pigeon [ProjectNative]/[PiniaNative] 访问原生脚本管理能力。
abstract class ScriptLifecycleToolHandler implements AiChatToolHandler {
  const ScriptLifecycleToolHandler(this.context);

  final ApkReverseToolRuntimeContext context;

  ProjectNative get _projectNative => ProjectNative();

  PiniaNative get _piniaNative => PiniaNative();

  String get _pkg => context.packageName;

  bool get _isZh => context.isZh;

  /// 校验 packageName 不为空
  void _requirePackage() {
    if (_pkg.isEmpty) {
      throw ArgumentError(
        _isZh ? '当前无目标应用，请先在 APK 逆向会话中打开一个应用'
            : 'No target app. Please open an APK in a reverse session first.',
      );
    }
  }
}

// ═══ A1. generate_xposed_hook ═══

class GenerateXposedHookHandler extends ScriptLifecycleToolHandler {
  const GenerateXposedHookHandler(super.context);

  @override
  String get toolName => 'generate_xposed_hook';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final className = call.getString('className');
    if (className.isEmpty) {
      throw ArgumentError('className 不能为空 / className is required');
    }

    final methodName = call.getString('methodName');
    final paramTypes = call.getStringList('parameterTypes');
    final hookType = call.getString('hookType', 'before_after');

    if (methodName.isNotEmpty) {
      return _genSingleMethod(className, methodName, paramTypes, hookType);
    } else {
      return _genAllMethods(className, paramTypes);
    }
  }

  String _genSingleMethod(
    String cls, String method, List<String> params, String hookType,
  ) {
    final paramList = params.join(', ');
    String template;
    switch (hookType) {
      case 'before':
        template = _xposedHookBefore;
      case 'after':
        template = _xposedHookAfter;
      case 'replace':
        template = _xposedHookReplace;
      case 'before_after':
      default:
        template = _xposedHookBeforeAfter;
    }
    return template
        .replaceAll('{className}', cls)
        .replaceAll('{methodName}', method)
        .replaceAll('{paramList}', paramList);
  }

  String _genAllMethods(String cls, List<String> params) {
    final paramListStr = params.join(', ');
    // 无 methodName 时生成方法枚举提示 + 骨架
    return _xposedMethodEnumTemplate
        .replaceAll('{className}', cls)
        .replaceAll(
          '{methodList}',
          _isZh
              ? '请先用 decompile_class 或 list_classes 查看 $cls 的方法列表，然后带 methodName 重新调用本工具'
              : 'Use decompile_class or list_classes to view methods of $cls, then call this tool again with methodName',
        )
        .replaceAll('{methodSkeletons}', _xposedMethodSkeleton
            .replaceAll('{className}', cls)
            .replaceAll('{methodName}', 'methodName')
            .replaceAll('{paramTypes}', paramListStr)
            .replaceAll('{paramListStr}', paramListStr));
  }
}

// ═══ A2. generate_frida_hook（升级版，替换 generate_so_hook） ═══

class GenerateFridaHookHandler extends ScriptLifecycleToolHandler {
  const GenerateFridaHookHandler(super.context);

  @override
  String get toolName => 'generate_frida_hook';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final mode = call.getString('mode', 'javaMethod');

    switch (mode) {
      case 'javaMethod':
        return _genJavaMethod(call);
      case 'jniSymbol':
        return _genJniSymbol(call);
      case 'address':
        return _genAddress(call);
      default:
        throw ArgumentError(
          'mode 非法，仅支持 javaMethod/jniSymbol/address / '
          'Invalid mode, only javaMethod/jniSymbol/address supported',
        );
    }
  }

  String _genJavaMethod(AiToolCall call) {
    final className = call.getString('className');
    final methodName = call.getString('methodName');
    final paramTypes = call.getStringList('parameterTypes');

    if (className.isEmpty) throw ArgumentError('className 不能为空');
    if (methodName.isEmpty) throw ArgumentError('methodName 不能为空');

    final overloadArgs = paramTypes.isNotEmpty
        ? paramTypes.map((t) => "'$t'").join(', ')
        : '';
    final paramList = paramTypes.asMap().entries
        .map((e) => 'p${e.key}')
        .join(', ');

    return _fridaJavaMethod
        .replaceAll('{className}', className)
        .replaceAll('{methodName}', methodName)
        .replaceAll('{overloadArgs}', overloadArgs)
        .replaceAll('{paramList}', paramList);
  }

  String _genJniSymbol(AiToolCall call) {
    final soPath = call.getString('soPath');
    final symbolName = call.getString('symbolName');

    if (soPath.isEmpty) throw ArgumentError('soPath 不能为空');
    if (symbolName.isEmpty) throw ArgumentError('symbolName 不能为空');

    final soName = soPath.split('/').last;

    return _fridaJniSymbol
        .replaceAll('{soName}', soName)
        .replaceAll('{symbolName}', symbolName);
  }

  String _genAddress(AiToolCall call) {
    final soPath = call.getString('soPath');
    final addressStr = call.getString('address');

    if (soPath.isEmpty) throw ArgumentError('soPath 不能为空');
    if (addressStr.isEmpty) throw ArgumentError('address 不能为空');

    final soName = soPath.split('/').last;
    final cleaned = addressStr.replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
    final addr = int.tryParse(cleaned, radix: 16);
    if (addr == null) {
      throw ArgumentError(
        'address 需为十六进制，如 0x1234 / address must be hexadecimal, e.g. 0x1234',
      );
    }

    return _fridaAddress
        .replaceAll('{soName}', soName)
        .replaceAll('{address}', addressStr)
        .replaceAll('{offset}', '0x${addr.toRadixString(16)}');
  }
}

// ═══ A4. save_script ═══

class SaveScriptHandler extends ScriptLifecycleToolHandler {
  const SaveScriptHandler(super.context);

  @override
  String get toolName => 'save_script';

  static const _reservedFrida = {'hook.js', 'loader.js'};
  static const _reservedXposed = {'hook.js', 'loader.js'};

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    _requirePackage();

    final scriptType = call.getString('scriptType');
    final fileName = call.getString('fileName');
    final code = call.getString('code');
    final overwrite = call.getBool('overwrite');

    if (scriptType.isEmpty) throw ArgumentError('scriptType 不能为空');
    if (fileName.isEmpty) throw ArgumentError('fileName 不能为空');
    if (code.isEmpty) throw ArgumentError('code 不能为空');

    // 校验保留名
    if (scriptType == 'frida' && _reservedFrida.contains(fileName) ||
        scriptType == 'xposed' && _reservedXposed.contains(fileName)) {
      throw ArgumentError(
        _isZh
            ? '$fileName 是保留文件名，请换一个 / $fileName is a reserved name'
            : '$fileName is a reserved name, please choose another',
      );
    }

    // 处理文件名：Frida 自动补 .js，Xposed 自动加 [tradition] 前缀
    String finalName;
    if (scriptType == 'frida') {
      finalName = fileName.endsWith('.js') ? fileName : '$fileName.js';
    } else {
      // xposed
      final base = fileName.endsWith('.js') ? fileName : '$fileName.js';
      finalName = base.startsWith('[') ? base : '[tradition]$base';
    }

    // 检查是否已存在（不 overwrite 时）
    if (!overwrite) {
      final existing = scriptType == 'frida'
          ? await _projectNative.getFridaScripts(_pkg)
          : await _projectNative.getJsScripts(_pkg);
      if (existing.contains(finalName)) {
        throw ArgumentError(
          _isZh
              ? '脚本 $finalName 已存在。设置 overwrite=true 覆盖 / '
                  'Script $finalName already exists. Set overwrite=true to overwrite'
              : 'Script $finalName already exists. Set overwrite=true to overwrite',
        );
      }
    }

    // 写盘
    if (scriptType == 'frida') {
      await _projectNative.createFridaScript(_pkg, code, finalName, false);
    } else {
      await _projectNative.createJsScript(_pkg, code, finalName, false);
    }

    // 默认启用
    final toggleKey = scriptType == 'frida'
        ? 'frida_check_status_${_pkg}_$finalName'
        : 'xposed_check_status_${_pkg}_$finalName';
    await _piniaNative.setBool(key: toggleKey, value: true);

    return _isZh
        ? '脚本 $finalName 已保存并启用'
        : 'Script $finalName saved and enabled';
  }
}

// ═══ A5. list_scripts ═══

class ListScriptsHandler extends ScriptLifecycleToolHandler {
  const ListScriptsHandler(super.context);

  @override
  String get toolName => 'list_scripts';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    _requirePackage();

    final scriptType = call.getString('scriptType');
    final showFrida = scriptType.isEmpty || scriptType == 'frida';
    final showXposed = scriptType.isEmpty || scriptType == 'xposed';

    final buf = StringBuffer();
    if (_isZh) {
      buf.writeln('## 脚本列表 - $_pkg\n');
    } else {
      buf.writeln('## Script List - $_pkg\n');
    }

    if (showFrida) {
      buf.writeln(_isZh ? '### Frida 脚本' : '### Frida Scripts');
      try {
        final fridaScripts = await _projectNative.getFridaScripts(_pkg);
        if (fridaScripts.isEmpty) {
          buf.writeln(_isZh ? '（无）\n' : '(none)\n');
        } else {
          for (final name in fridaScripts) {
            final enabled = await _piniaNative.getBool(
              key: 'frida_check_status_${_pkg}_$name',
              defaultValue: false,
            );
            buf.writeln(
              '- $name ${enabled ? (_isZh ? '✅ 启用' : '✅ enabled') : (_isZh ? '⏸️ 停用' : '⏸️ disabled')}',
            );
          }
          buf.writeln();
        }
      } catch (e) {
        buf.writeln('${_isZh ? '加载失败' : 'Load failed'}: $e\n');
      }
    }

    if (showXposed) {
      buf.writeln(_isZh ? '### Xposed 脚本' : '### Xposed Scripts');
      try {
        final xposedScripts = await _projectNative.getJsScripts(_pkg);
        if (xposedScripts.isEmpty) {
          buf.writeln(_isZh ? '（无）\n' : '(none)\n');
        } else {
          for (final name in xposedScripts) {
            final enabled = await _piniaNative.getBool(
              key: 'xposed_check_status_${_pkg}_$name',
              defaultValue: false,
            );
            buf.writeln(
              '- $name ${enabled ? (_isZh ? '✅ 启用' : '✅ enabled') : (_isZh ? '⏸️ 停用' : '⏸️ disabled')}',
            );
          }
          buf.writeln();
        }
      } catch (e) {
        buf.writeln('${_isZh ? '加载失败' : 'Load failed'}: $e\n');
      }
    }

    return buf.toString().trimRight();
  }
}

// ═══ A6. toggle_script ═══

class ToggleScriptHandler extends ScriptLifecycleToolHandler {
  const ToggleScriptHandler(super.context);

  @override
  String get toolName => 'toggle_script';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    _requirePackage();

    final scriptType = call.getString('scriptType');
    final fileName = call.getString('fileName');
    final enabled = call.getBool('enabled', true);

    if (scriptType.isEmpty) throw ArgumentError('scriptType 不能为空');
    if (fileName.isEmpty) throw ArgumentError('fileName 不能为空');

    // 验证脚本存在
    final scripts = scriptType == 'frida'
        ? await _projectNative.getFridaScripts(_pkg)
        : await _projectNative.getJsScripts(_pkg);
    if (!scripts.contains(fileName)) {
      throw ArgumentError(
        _isZh
            ? '脚本 $fileName 不存在 / Script $fileName not found'
            : 'Script $fileName not found',
      );
    }

    final toggleKey = scriptType == 'frida'
        ? 'frida_check_status_${_pkg}_$fileName'
        : 'xposed_check_status_${_pkg}_$fileName';
    await _piniaNative.setBool(key: toggleKey, value: enabled);

    return _isZh
        ? '脚本 $fileName 已${enabled ? "启用" : "停用"}'
        : 'Script $fileName ${enabled ? "enabled" : "disabled"}';
  }
}

// ═══ A3. validate_script（P1） ═══

class ValidateScriptHandler extends ScriptLifecycleToolHandler {
  const ValidateScriptHandler(super.context);

  @override
  String get toolName => 'validate_script';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    final code = call.getString('code');
    final engine = call.getString('engine', 'frida');

    if (code.isEmpty) throw ArgumentError('code 不能为空');

    final issues = <String>[];

    // ═══ 通用 JS 语法校验 ═══
    _checkBrackets(code, issues);
    _checkQuotes(code, issues);
    _checkKeywords(code, issues);
    _checkSyntax(code, engine, issues);

    if (issues.isEmpty) {
      return _isZh
          ? '校验通过，未发现语法问题。'
          : 'Validation passed, no syntax issues found.';
    }

    final buf = StringBuffer();
    if (_isZh) {
      buf.writeln('发现 ${issues.length} 个问题：\n');
    } else {
      buf.writeln('Found ${issues.length} issues:\n');
    }
    for (final issue in issues) {
      buf.writeln('- $issue');
    }
    return buf.toString().trimRight();
  }

  void _checkBrackets(String code, List<String> issues) {
    int brace = 0, bracket = 0, paren = 0;
    for (var i = 0; i < code.length; i++) {
      switch (code[i]) {
        case '{': brace++; break;
        case '}': brace--; break;
        case '[': bracket++; break;
        case ']': bracket--; break;
        case '(': paren++; break;
        case ')': paren--; break;
      }
    }
    if (brace != 0) issues.add('${_isZh ? "花括号 {}" : "Braces {}"} ${_isZh ? "不匹配" : "unmatched"} (差值/$brace)');
    if (bracket != 0) issues.add('${_isZh ? "方括号 []" : "Brackets []"} ${_isZh ? "不匹配" : "unmatched"} (差值/$bracket)');
    if (paren != 0) issues.add('${_isZh ? "圆括号 ()" : "Parentheses ()"} ${_isZh ? "不匹配" : "unmatched"} (差值/$paren)');
  }

  void _checkQuotes(String code, List<String> issues) {
    int single = 0, double = 0, backtick = 0;
    bool inSingle = false, inDouble = false, inBacktick = false;
    for (var i = 0; i < code.length; i++) {
      final c = code[i];
      final prev = i > 0 ? code[i - 1] : '';
      final escaped = prev == '\\';

      if (!escaped) {
        if (c == "'" && !inDouble && !inBacktick) inSingle = !inSingle;
        if (c == '"' && !inSingle && !inBacktick) inDouble = !inDouble;
        if (c == '`' && !inSingle && !inDouble) inBacktick = !inBacktick;
      }
      if (c == "'" && !inDouble && !inBacktick) single++;
      if (c == '"' && !inSingle && !inBacktick) double++;
      if (c == '`' && !inSingle && !inDouble) backtick++;
    }
    if (inSingle) issues.add(_isZh ? '单引号未闭合' : 'Unclosed single quote');
    if (inDouble) issues.add(_isZh ? '双引号未闭合' : 'Unclosed double quote');
    if (inBacktick) issues.add(_isZh ? '模板字符串未闭合' : 'Unclosed template literal');
  }

  void _checkKeywords(String code, List<String> issues) {
    // Fx 糖特有校验
    if (code.contains('Java.use(') || code.contains('Java.perform(')) {
      issues.add(
        _isZh
            ? '发现原生 Frida API (Java.use/Java.perform)，请使用 Fx 糖 API (Fx.use/Fx.hookNative) 替代'
            : 'Found raw Frida API (Java.use/Java.perform). Use Fx sugar API (Fx.use/Fx.hookNative) instead.',
      );
    }
    // Jx 糖特有校验
    if (code.contains('XposedBridge') || code.contains('XposedHelpers')) {
      issues.add(
        _isZh
            ? '发现原生 Xposed API，请使用 Jx 糖 API (Jx.use) 替代'
            : 'Found raw Xposed API. Use Jx sugar API (Jx.use) instead.',
      );
    }
  }

  void _checkSyntax(String code, String engine, List<String> issues) {
    // 检查是否有明显的语法错误标记
    if (code.contains('function(') && !code.contains('function (')) {
      // 只是风格提示，不报错
    }
    // engine 特定校验
    if (engine == 'xposed') {
      if (!code.contains('[tradition]')) {
        issues.add(
          _isZh
              ? '提示：Xposed 脚本建议以 [tradition] 前缀命名文件'
              : 'Hint: Xposed scripts should use the [tradition] filename prefix',
        );
      }
    }
  }
}

// ═══ A7. read_script ═══

class ReadScriptHandler extends ScriptLifecycleToolHandler {
  const ReadScriptHandler(super.context);

  @override
  String get toolName => 'read_script';

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    _requirePackage();

    final scriptType = call.getString('scriptType');
    final fileName = call.getString('fileName');

    if (scriptType.isEmpty) throw ArgumentError('scriptType 不能为空');
    if (fileName.isEmpty) throw ArgumentError('fileName 不能为空');

    final scripts = scriptType == 'frida'
        ? await _projectNative.getFridaScripts(_pkg)
        : await _projectNative.getJsScripts(_pkg);
    if (!scripts.contains(fileName)) {
      throw ArgumentError(
        '${_isZh ? "脚本 $fileName 不存在" : "Script $fileName not found"}',
      );
    }

    final content = scriptType == 'frida'
        ? await _projectNative.readFridaScript(_pkg, fileName)
        : await _projectNative.readJsScript(_pkg, fileName);

    return content;
  }
}

// ═══ A8. delete_script ═══

class DeleteScriptHandler extends ScriptLifecycleToolHandler {
  const DeleteScriptHandler(super.context);

  @override
  String get toolName => 'delete_script';

  static const _reservedNames = {'hook.js', 'loader.js'};

  @override
  Future<String> handle(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    _requirePackage();

    final scriptType = call.getString('scriptType');
    final fileName = call.getString('fileName');
    final confirm = call.getBool('confirm');

    if (scriptType.isEmpty) throw ArgumentError('scriptType 不能为空');
    if (fileName.isEmpty) throw ArgumentError('fileName 不能为空');
    if (!confirm) {
      throw ArgumentError(
        _isZh
            ? '删除操作需 confirm=true 确认'
            : 'Delete requires confirm=true',
      );
    }

    if (_reservedNames.contains(fileName)) {
      throw ArgumentError(
        _isZh ? '不能删除保留文件 $fileName' : 'Cannot delete reserved file $fileName',
      );
    }

    final scripts = scriptType == 'frida'
        ? await _projectNative.getFridaScripts(_pkg)
        : await _projectNative.getJsScripts(_pkg);
    if (!scripts.contains(fileName)) {
      throw ArgumentError(
        '${_isZh ? "脚本 $fileName 不存在" : "Script $fileName not found"}',
      );
    }

    if (scriptType == 'frida') {
      await _projectNative.deleteFridaScript(_pkg, fileName);
    } else {
      await _projectNative.deleteJsScript(_pkg, fileName);
    }

    return _isZh
        ? '脚本 $fileName 已删除'
        : 'Script $fileName deleted';
  }
}