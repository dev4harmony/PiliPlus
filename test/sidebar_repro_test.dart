import 'package:flutter/material.dart' hide NavigationDrawer, NavigationDrawerDestination;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('tablet sidebar reproduces drawer layout assert', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(left: 12)),
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                // 复刻 main/view.dart _sideBar 的平板分支
                Builder(
                  builder: (context) {
                    const left = 12.0;
                    final Widget sideBar = Column(
                      children: [
                        const SizedBox(height: 25),
                        Column(
                          children: [
                            const Icon(Icons.person),
                            const SizedBox(height: 8),
                            IconButton(
                              onPressed: () {},
                              icon: const Icon(Icons.search),
                            ),
                          ],
                        ),
                        const Spacer(flex: 2),
                        // 修复后结构：抽屉由 Expanded 提供有界高度
                        Expanded(
                          flex: 5,
                          child: SizedBox(
                            width: 130,
                            child: NavigationDrawer(
                              flex: 5,
                              backgroundColor: Colors.transparent,
                              tilePadding: const EdgeInsets.symmetric(
                                vertical: 5,
                                horizontal: 12,
                              ),
                              indicatorShape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(16),
                                ),
                              ),
                              onDestinationSelected: (_) {},
                              selectedIndex: 0,
                              children: [
                                NavigationDrawerDestination(
                                  label: const Text('首页'),
                                  icon: const Icon(Icons.home_outlined),
                                  selectedIcon: const Icon(Icons.home),
                                ),
                                NavigationDrawerDestination(
                                  label: const Text('动态'),
                                  icon: const Icon(Icons.flash_on_outlined),
                                  selectedIcon: const Icon(Icons.dynamic_feed),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                    final Widget child = MediaQuery.removePadding(
                      context: context,
                      removeLeft: true,
                      removeRight: true,
                      child: sideBar,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(left: left),
                      child: child,
                    );
                  },
                ),
                const VerticalDivider(width: 1),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  });
}
