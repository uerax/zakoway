/// 认证提供商类型枚举：
/// 当前阶段支持：
/// - guest: 游客模式（基于本机专属设备标识）
/// - bangumi: Bangumi 访问令牌登录
/// 预留扩展类型：
/// - zakoway: 未来自建/官方统一账号系统
enum AuthProviderType {
  guest('guest', '游客'),
  bangumi('bangumi', 'Bangumi'),
  zakoway('zakoway', 'Zakoway');

  final String id;
  final String label;

  const AuthProviderType(this.id, this.label);

  static AuthProviderType fromId(String? id) {
    if (id == null) return AuthProviderType.guest;
    for (final v in AuthProviderType.values) {
      if (v.id == id) return v;
    }
    return AuthProviderType.guest;
  }
}
