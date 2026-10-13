import 'package:flutter/material.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';
import 'player_panel_widgets.dart';

enum _DanmakuTab { search, settings, import }

/// 全功能三 Tab 弹幕设置与控制面板 (1:1 对齐 animaku DanmakuPanel)
class PlayerDanmakuPanelBody extends StatefulWidget {
  const PlayerDanmakuPanelBody({
    super.key,
    this.danmakuController,
    this.coordinator,
    required this.primaryColor,
  });

  final DanmakuController? danmakuController;
  final DanmakuSessionCoordinator? coordinator;
  final Color primaryColor;

  @override
  State<PlayerDanmakuPanelBody> createState() => _PlayerDanmakuPanelBodyState();
}

class _PlayerDanmakuPanelBodyState extends State<PlayerDanmakuPanelBody> {
  _DanmakuTab _currentTab = _DanmakuTab.settings;

  // 搜索输入
  final TextEditingController _searchController = TextEditingController();

  // B 站手动输入
  final TextEditingController _bvInputController = TextEditingController();
  final TextEditingController _bvPageController = TextEditingController(text: '1');

  // 屏蔽词输入
  final TextEditingController _filterInputController = TextEditingController();

  // 时间轴校准目标 (null 表示全局，否则对应指定源池)
  DanmakuPoolId? _selectedOffsetTarget;

  @override
  void initState() {
    super.initState();
    final coord = widget.coordinator;
    if (coord != null && coord.animes.isEmpty && coord.status.contains('未匹配')) {
      _currentTab = _DanmakuTab.search;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bvInputController.dispose();
    _bvPageController.dispose();
    _filterInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.danmakuController ?? widget.coordinator?.danmakuController;
    if (controller == null) {
      return const Padding(
        padding: EdgeInsets.all(20.0),
        child: Center(
          child: Text(
            '当前未挂载弹幕组件',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    }

    final coord = widget.coordinator;

    return ListenableBuilder(
      listenable: Listenable.merge([
        controller,
        ?coord,
        ?coord?.poolsManager,
      ]),
      builder: (context, _) {
        final cfg = controller.settings;
        final totalCount = coord != null ? coord.poolsManager.totalLoadedCount : controller.items.length;
        final shownCount = controller.items.length;
        final statusText = coord?.status ?? '—';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. 顶部 Tab 栏
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _buildTabButton(_DanmakuTab.search, '弹弹搜索'),
                    _buildTabButton(_DanmakuTab.settings, '基础设置'),
                    _buildTabButton(_DanmakuTab.import, '导入/屏蔽'),
                  ],
                ),
              ),
            ),

            // 2. 状态信息指示栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              color: Colors.white.withValues(alpha: 0.03),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      statusText,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (totalCount > 0)
                    Text(
                      shownCount != totalCount ? '$shownCount/$totalCount条' : '$totalCount条',
                      style: TextStyle(
                        color: widget.primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                ],
              ),
            ),

            const Divider(color: Color(0x15FFFFFF), height: 1, thickness: 0.5),

            // 3. Tab 主体内容
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: switch (_currentTab) {
                _DanmakuTab.search => _buildSearchTab(coord),
                _DanmakuTab.settings => _buildSettingsTab(controller, coord, cfg),
                _DanmakuTab.import => _buildImportTab(coord, controller, cfg),
              },
            ),

            // 4. 底部源池状态栏 Chips
            if (coord != null)
              DanmakuSourceChipsBar(
                chips: coord.poolsManager.getSourceChips(),
                onToggleSource: (id) => coord.poolsManager.togglePool(id),
                primaryColor: widget.primaryColor,
              ),
          ],
        );
      },
    );
  }

  Widget _buildTabButton(_DanmakuTab tab, String label) {
    final selected = _currentTab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _currentTab = tab),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? widget.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white60,
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  // ==========================
  // Tab 1: 弹弹搜索
  // ==========================
  Widget _buildSearchTab(DanmakuSessionCoordinator? coord) {
    if (coord == null) {
      return const Center(
        child: Text('当前环境未启用在线搜索会话', style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const PanelSectionHeader(title: '弹弹play 番剧搜索'),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: '搜索番剧名称…',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: widget.primaryColor),
                    ),
                  ),
                  onSubmitted: (kw) => coord.searchDandan(kw),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: coord.searchBusy
                  ? null
                  : () => coord.searchDandan(_searchController.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                minimumSize: const Size(0, 36),
              ),
              child: Text(coord.searchBusy ? '…' : '搜索', style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // 选择番剧下拉
        const Text('选择番剧', style: TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        _buildDropdownContainer(
          hint: '选择番剧…',
          value: coord.selectedAnimeId,
          items: coord.animes.map((a) {
            final desc = a.typeDescription != null ? ' (${a.typeDescription})' : '';
            return DropdownMenuItem<int>(
              value: a.animeId,
              child: Text('${a.animeTitle}$desc', overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) coord.pickDandanAnime(val);
          },
        ),

        const SizedBox(height: 10),

        // 选择章节下拉
        const Text('选择章节', style: TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        _buildDropdownContainer(
          hint: '选择章节…',
          value: coord.selectedEpisodeId,
          items: coord.episodes.map((ep) {
            return DropdownMenuItem<int>(
              value: ep.episodeId,
              child: Text(ep.episodeTitle, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) coord.pickDandanEpisode(val);
          },
        ),

        // 偏移校准提示与重置
        if (coord.danmakuOffset != 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('⚡', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 6),
                    Text(
                      '已校准集数偏移: ${coord.danmakuOffset > 0 ? "+${coord.danmakuOffset}" : coord.danmakuOffset} 集',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => coord.resetDanmakuOffset(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('重置偏移', style: TextStyle(color: Colors.amber, fontSize: 11)),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 10),
        const Text(
          '弹弹play 匹配写入「弹弹」基准源。可在底部开关各源，或在设置页对齐时间轴。',
          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
        ),
      ],
    );
  }

  // ==========================
  // Tab 2: 弹幕设置
  // ==========================
  Widget _buildSettingsTab(
    DanmakuController controller,
    DanmakuSessionCoordinator? coord,
    DanmakuSettings cfg,
  ) {
    // 动态可调节时移的源列表 (全局 + loaded 的源)
    final availableTargets = <({DanmakuPoolId? id, String label, int offsetMs})>[
      (id: null, label: '全局', offsetMs: coord?.poolsManager.globalTimeOffsetMs ?? 0),
    ];

    if (coord != null) {
      for (final chip in coord.poolsManager.getSourceChips()) {
        if (chip.loaded) {
          availableTargets.add((id: chip.id, label: chip.label, offsetMs: chip.timeOffsetMs));
        }
      }
    }

    final curTarget = _selectedOffsetTarget;
    final curOffsetMs = curTarget == null
        ? (coord?.poolsManager.globalTimeOffsetMs ?? 0)
        : (coord?.poolsManager.getPool(curTarget).timeOffsetMs ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. 时间轴校准中心 (Offset Stepper)
        if (coord != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '时间轴校准 (Offset)',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    InkWell(
                      onTap: () {
                        coord.poolsManager.globalTimeOffsetMs = 0;
                        for (final id in DanmakuPoolId.values) {
                          coord.poolsManager.setPoolOffset(id, 0);
                        }
                      },
                      child: const Text('全部归零', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 目标源切换 Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: availableTargets.map((t) {
                      final isSelected = _selectedOffsetTarget == t.id;
                      final hasShift = t.offsetMs != 0;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () => setState(() => _selectedOffsetTarget = t.id),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? widget.primaryColor
                                  : Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  t.label,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white70,
                                    fontSize: 11.5,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                if (hasShift) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.white.withValues(alpha: 0.3) : widget.primaryColor.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${(t.offsetMs / 1000).toStringAsFixed(1)}s',
                                      style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'monospace'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 8),

                // 步进器
                DanmakuOffsetStepper(
                  offsetMs: curOffsetMs,
                  subLabel: curTarget == null
                      ? '作用于所有源（修复视频自带片头时差）'
                      : '单独调节当前源时间轴',
                  primaryColor: widget.primaryColor,
                  onChanged: (newMs) {
                    if (curTarget == null) {
                      coord.poolsManager.globalTimeOffsetMs = newMs;
                    } else {
                      coord.poolsManager.setPoolOffset(curTarget, newMs);
                    }
                  },
                  onReset: () {
                    if (curTarget == null) {
                      coord.poolsManager.globalTimeOffsetMs = 0;
                    } else {
                      coord.poolsManager.setPoolOffset(curTarget, 0);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 2. 基础开关
        const PanelSectionHeader(title: '基础开关'),
        PanelSwitchRow(
          title: '显示弹幕',
          subtitle: '开启或关闭屏幕所有弹幕',
          value: cfg.enabled,
          primaryColor: widget.primaryColor,
          onChanged: (val) => controller.updateSettings(cfg.copyWith(enabled: val)),
        ),
        PanelSwitchRow(
          title: '智能精简',
          subtitle: '自动抑制重复刷屏与重叠',
          value: cfg.simplify,
          primaryColor: widget.primaryColor,
          onChanged: (val) => controller.updateSettings(cfg.copyWith(simplify: val)),
        ),
        PanelSwitchRow(
          title: '屏蔽彩色弹幕',
          subtitle: '统一渲染为高对比度白色',
          value: cfg.hideColor,
          primaryColor: widget.primaryColor,
          onChanged: (val) => controller.updateSettings(cfg.copyWith(hideColor: val)),
        ),

        const SizedBox(height: 10),

        // 3. 显示范围
        const PanelSectionHeader(title: '显示范围'),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              PanelOptionChip(
                label: '半屏 (50%)',
                selected: (cfg.area - 0.5).abs() < 0.05,
                primaryColor: widget.primaryColor,
                onTap: () => controller.updateSettings(cfg.copyWith(area: 0.5)),
              ),
              PanelOptionChip(
                label: '3/4 屏',
                selected: (cfg.area - 0.75).abs() < 0.05,
                primaryColor: widget.primaryColor,
                onTap: () => controller.updateSettings(cfg.copyWith(area: 0.75)),
              ),
              PanelOptionChip(
                label: '全屏',
                selected: (cfg.area - 1.0).abs() < 0.05,
                primaryColor: widget.primaryColor,
                onTap: () => controller.updateSettings(cfg.copyWith(area: 1.0)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // 4. 视觉调节
        const PanelSectionHeader(title: '视觉调节'),
        PanelSliderRow(
          title: '不透明度',
          valText: '${(cfg.opacity * 100).round()}%',
          value: cfg.opacity,
          min: 0.2,
          max: 1.0,
          primaryColor: widget.primaryColor,
          onChanged: (v) => controller.updateSettings(cfg.copyWith(opacity: v)),
        ),
        PanelSliderRow(
          title: '弹幕字号',
          valText: '${(cfg.fontSizeScale * 100).round()}%',
          value: cfg.fontSizeScale,
          min: 0.7,
          max: 1.4,
          primaryColor: widget.primaryColor,
          onChanged: (v) => controller.updateSettings(cfg.copyWith(fontSizeScale: v)),
        ),
        PanelSliderRow(
          title: '飞行速度',
          valText: '${cfg.speed.toStringAsFixed(1)}x',
          value: cfg.speed,
          min: 0.6,
          max: 1.6,
          primaryColor: widget.primaryColor,
          onChanged: (v) => controller.updateSettings(cfg.copyWith(speed: v)),
        ),

        const SizedBox(height: 10),

        // 5. 弹幕类型屏蔽
        const PanelSectionHeader(title: '弹幕类型屏蔽'),
        Row(
          children: [
            Expanded(
              child: PanelCheckboxChip(
                label: '屏蔽滚动',
                checked: cfg.hideScroll,
                primaryColor: widget.primaryColor,
                onTap: () => controller.updateSettings(cfg.copyWith(hideScroll: !cfg.hideScroll)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: PanelCheckboxChip(
                label: '屏蔽顶部',
                checked: cfg.hideTop,
                primaryColor: widget.primaryColor,
                onTap: () => controller.updateSettings(cfg.copyWith(hideTop: !cfg.hideTop)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: PanelCheckboxChip(
                label: '屏蔽底部',
                checked: cfg.hideBottom,
                primaryColor: widget.primaryColor,
                onTap: () => controller.updateSettings(cfg.copyWith(hideBottom: !cfg.hideBottom)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==========================
  // Tab 3: 导入/屏蔽
  // ==========================
  Widget _buildImportTab(
    DanmakuSessionCoordinator? coord,
    DanmakuController controller,
    DanmakuSettings cfg,
  ) {
    final biliManualOffset = coord?.poolsManager.getPool(DanmakuPoolId.bilibiliManual).timeOffsetMs ?? 0;
    final uploadOffset = coord?.poolsManager.getPool(DanmakuPoolId.upload).timeOffsetMs ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Bilibili 追加
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Bilibili 视频 / 番剧链接',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _bvInputController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'BV号 / ep86012 / ss28277 / av号 / 完整链接',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: widget.primaryColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('分P: ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  SizedBox(
                    width: 46,
                    height: 28,
                    child: TextField(
                      controller: _bvPageController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: coord?.bilibiliBusy == true
                        ? null
                        : () {
                            final page = int.tryParse(_bvPageController.text.trim()) ?? 1;
                            coord?.loadBilibiliManual(_bvInputController.text, page: page);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      minimumSize: const Size(0, 30),
                    ),
                    child: Text(
                      coord?.bilibiliBusy == true ? '拉取中…' : '追加 B 站弹幕',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              DanmakuOffsetStepper(
                offsetMs: biliManualOffset,
                label: 'B站源独立时移',
                subLabel: '校准剪辑/片头差异',
                primaryColor: widget.primaryColor,
                onChanged: (v) => coord?.poolsManager.setPoolOffset(DanmakuPoolId.bilibiliManual, v),
                onReset: () => coord?.poolsManager.setPoolOffset(DanmakuPoolId.bilibiliManual, 0),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // 2. 本地 XML 导入
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '本地 XML 弹幕文件',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => coord?.loadLocalXml(),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15), style: BorderStyle.solid),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text('📁', style: TextStyle(fontSize: 14)),
                          SizedBox(width: 6),
                          Text('选择本地 XML 弹幕文件', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                      Text('B站 / pakku', style: TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              DanmakuOffsetStepper(
                offsetMs: uploadOffset,
                label: 'XML源独立时移',
                primaryColor: widget.primaryColor,
                onChanged: (v) => coord?.poolsManager.setPoolOffset(DanmakuPoolId.upload, v),
                onReset: () => coord?.poolsManager.setPoolOffset(DanmakuPoolId.upload, 0),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // 3. 屏蔽词管理
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '屏蔽词列表 · ${cfg.filters.length} 条',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _filterInputController,
                        style: const TextStyle(color: Colors.white, fontSize: 11.5),
                        decoration: InputDecoration(
                          hintText: '关键词 或 /regex/',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onSubmitted: (_) => _addFilterRule(controller, cfg),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _addFilterRule(controller, cfg),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('添加', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              if (cfg.filters.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: cfg.filters.map((rule) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(rule, style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () {
                              final next = List<String>.from(cfg.filters)..remove(rule);
                              controller.updateSettings(cfg.copyWith(filters: next));
                            },
                            child: const Text('✕', style: TextStyle(color: Colors.redAccent, fontSize: 10)),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _addFilterRule(DanmakuController controller, DanmakuSettings cfg) {
    final text = _filterInputController.text.trim();
    if (text.isEmpty) return;
    if (!cfg.filters.contains(text)) {
      final next = List<String>.from(cfg.filters)..add(text);
      controller.updateSettings(cfg.copyWith(filters: next));
    }
    _filterInputController.clear();
  }

  Widget _buildDropdownContainer<T>({
    required String hint,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          isExpanded: true,
          dropdownColor: const Color(0xFF1E222D),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
