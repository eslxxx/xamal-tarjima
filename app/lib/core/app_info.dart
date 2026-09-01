/// App 自己的名字和版本号。
///
/// 单独放一个文件是因为这两个值散在好几处: 启动器名 (AndroidManifest 的
/// android:label)、任务切换器名 (MaterialApp.title)、首页和引导页的大标题、
/// 关于页、统计上报的 User-Agent 和 app_version 字段。
/// 除了 AndroidManifest 那处 (XML 里没法引 Dart 常量), 其余都从这里取。
library;

/// 应用名。改这里之后**记得同步改** android/app/src/main/AndroidManifest.xml
/// 的 android:label。
const String kAppName = 'XAMAL离线翻译';

/// 开发者署名, 显示在设置入口页最下方和关于页。
const String kVendor = 'xamal-soft';

/// 关于页里的开发者全称与联系方式。
const String kTeam = 'XAMAL 应用开发团队';
const String kContactQQ = '657400454';

/// 当前版本号。改这里之后**记得同步改** pubspec.yaml 的 version。
const String kAppVersion = '1.0.0';
