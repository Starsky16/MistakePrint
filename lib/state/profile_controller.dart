import 'package:flutter/widgets.dart';

import '../profiles/paper_profile.dart';
import '../profiles/presets.dart';
import '../profiles/profile_store.dart';

/// 当前生效的机型档案：内存态 + 落盘（计划 §5.5、P3 提交 3「状态共享」）。
///
/// 不引第三方状态库：这里只有一个 ChangeNotifier，配 [ProfileScope] 就够，出图与
/// 预览页只需要「拿到当前档案」与「被通知重建」这两件事。
class ProfileController extends ChangeNotifier {
  ProfileController({this.store = const ProfileStore()});

  final ProfileStore store;

  PaperProfile _profile = kPaperangP1Default;
  bool _loaded = false;

  /// 当前档案。首次 [load] 之前是保守默认值，未校准机型也能直接出图。
  PaperProfile get profile => _profile;

  /// 当前档案对应的细线增强档位；裸参数被改过则为 null（自定义）。
  ThinLinePreset? get thinLinePreset => detectThinLinePreset(_profile);

  /// 是否已从存档读过一次。开发者模式用它区分「还没读」与「读出来就是默认值」。
  bool get isLoaded => _loaded;

  /// 读存档。仓储层的降级（缺文件 / 内容坏）在 [ProfileStore] 里做完，这里不重复。
  Future<void> load() async {
    _profile = await store.load();
    _loaded = true;
    notifyListeners();
  }

  /// 换一份档案并落盘。
  ///
  /// 先通知后落盘：界面立刻响应，写文件失败时异常抛给调用方去提示用户
  /// （内存态仍然是用户刚选的值，不会出现「点了没反应」）。
  Future<void> update(PaperProfile profile) async {
    _profile = profile;
    notifyListeners();
    await store.save(profile);
  }

  /// 按档位展开裸参数（档位表是唯一真相，见 `presets.dart`）。
  Future<void> setThinLinePreset(ThinLinePreset preset) =>
      update(applyThinLinePreset(_profile, preset));

  /// 一键回默认值（向导里的「重置」）。
  Future<void> resetToDefault() => update(kPaperangP1Default);
}

/// 把 [ProfileController] 递给整棵树。
///
/// `InheritedNotifier` 会在控制器通知时重建依赖它的页面，所以各页面只要
/// `ProfileScope.of(context).profile` 就能拿到最新档案，不需要额外的状态库。
class ProfileScope extends InheritedNotifier<ProfileController> {
  const ProfileScope({
    super.key,
    required ProfileController controller,
    required super.child,
  }) : super(notifier: controller);

  static ProfileController of(BuildContext context) {
    final ProfileScope? scope =
        context.dependOnInheritedWidgetOfExactType<ProfileScope>();
    assert(scope != null, 'ProfileScope 未挂载：需要在应用根部包一层。');
    return scope!.notifier!;
  }
}