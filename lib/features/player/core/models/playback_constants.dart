/// 播放控制层重写：时间常量与预算集中配置表
///
/// 遵循 docs/player-rewrite/04-error-policy.md (v3.1) 第五节规范
/// 严格集中管理所有时间预算、超时阈值与完成容差常量，杜绝代码中出现硬编码魔数。
library;

/// 直链解析单次超时上限 (3.5 秒，与 04 预算表对齐)
const Duration kResolvingTimeout = Duration(milliseconds: 3500);

/// 中途卡顿重缓冲超时上限 (30 秒，待评审)
const Duration kRebufferingTimeout = Duration(seconds: 30);

/// UI 换线提示条弹出等待时长 (5.0 秒)
///
/// 达到 5.0 秒画面未出时，UI 主动弹出【切换线路】提示条，播放器后台继续等待
const Duration kFirstFrameCoverPromptWait = Duration(seconds: 5);

/// 首帧出画等待硬上限 / 打开阶段看门狗超时 (12.0 秒)
///
/// 针对慢响应头场景（实测 9.045s），超时必须 >= 10s 以免误杀合法慢起播；
/// 满 12.0 秒无存活证据时看门狗强制熔断
const Duration kFirstFrameTimeout = Duration(seconds: 12);

/// 自愈恢复退避等待时延 (500 毫秒)
const Duration kRecoveryBackoffDelay = Duration(milliseconds: 500);

/// 会话端到端全局绝对硬上限总预算 (13.0 秒)
///
/// 从用户点击起到首个确定性终态（出画或弹出错误卡片）的全局绝对上限
const Duration kTotalBudget = Duration(seconds: 13);

/// 动态剩余预算自愈阈值 (5.0 秒)
///
/// 发生可恢复错误时，若 `remaining = 13.0s - elapsed < 5.0s`，立即放弃自愈重试直接转入 error
const Duration kMinRemainingBudgetForRecovery = Duration(seconds: 5);

/// 自然完播进度容差 (2.0 秒)
///
/// 当 `currentPos >= totalDur - kCompletedTolerance` 时视为自然播放完毕
const Duration kCompletedTolerance = Duration(seconds: 2);

/// 异常 EOF 回环死锁位移判断阈值 (1.0 秒)
///
/// 续播后在与上次断流相近位置（位移 < 1.0s）再次收到 EOF，判定为真实断流终点
const Duration kEofLoopProgressThreshold = Duration(seconds: 1);

/// 异常 EOF 允许自愈的最大次数 (1 次)
const int kMaxEofRecoveryAttempts = 1;
