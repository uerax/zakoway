import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/update_manager.dart';

/// 全局应用更新状态提供者
final updateManagerProvider = Provider<UpdateManager>((ref) {
  return UpdateManager.instance;
});
