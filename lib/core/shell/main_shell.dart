import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gua_pos/features/products/product_list_screen.dart';
import 'package:gua_pos/features/reports/reports_screen.dart';
// 1. Thay thế import SessionListScreen cũ bằng LivestreamHubScreen mới
import '../../features/livestream/presentation/livestream_hub_screen.dart';
import '../../features/orders/presentation/orders_list_screen.dart';

// ============================================================
// MAIN SHELL – Bottom Navigation 4 tab
// Tab: Livestream | Đơn hàng | Kho cây | Báo cáo
// ============================================================

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  // 2. Cập nhật trang đầu tiên của IndexedStack thành LivestreamHubScreen
  // Đồng thời bỏ từ khóa 'const' ở mảng vì LivestreamHubScreen không phải là hằng số biên dịch
  final List<Widget> _pages = [
    const LivestreamHubScreen(), // Hệ thống quản lý Live chia 2 nền tảng & Vòng quay realtime
    const OrdersScreen(),
    const ProductListScreen(),
    const ReportsScreen(),
  ];

  static const _tabs = [
    _TabItem(
      icon: CupertinoIcons.play_rectangle,
      activeIcon: CupertinoIcons.play_rectangle_fill,
      label: 'Live',
    ),
    _TabItem(
      icon: CupertinoIcons.doc_text,
      activeIcon: CupertinoIcons.doc_text_fill,
      label: 'Đơn hàng',
    ),
    _TabItem(
      icon: CupertinoIcons.leaf_arrow_circlepath,
      activeIcon: CupertinoIcons.leaf_arrow_circlepath,
      label: 'Kho cây',
    ),
    _TabItem(
      icon: CupertinoIcons.chart_bar,
      activeIcon: CupertinoIcons.chart_bar_fill,
      label: 'Báo cáo',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        tabs: _tabs,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

// ── Bottom Nav custom iOS style ──────────────────────────────
class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final List<_TabItem> tabs;
  final ValueChanged<int> onTap;

  const _BottomNav({
    required this.currentIndex,
    required this.tabs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: List.generate(tabs.length, (i) {
              final tab = tabs[i];
              final selected = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          selected ? tab.activeIcon : tab.icon,
                          key: ValueKey(selected),
                          size: 24,
                          // Áp dụng chuẩn màu sắc nhất quán với hệ thống cũ của bạn
                          color: selected
                              ? const Color(0xFF007AFF)
                              : Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tab.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected
                              ? const Color(0xFF007AFF)
                              : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
