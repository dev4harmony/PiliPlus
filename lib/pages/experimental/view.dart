import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/pages/setting/models/experimental_settings.dart';
import 'package:material_ui/material_ui.dart';

class ExperimentalPage extends StatefulWidget {
  const ExperimentalPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<ExperimentalPage> createState() => _ExperimentalPageState();
}

class _ExperimentalPageState extends State<ExperimentalPage> {
  final settings = experimentalSettings;

  @override
  Widget build(BuildContext context) {
    final showAppBar = widget.showAppBar;
    final padding = MediaQuery.viewPaddingOf(context);
    return SimpleScaffold(
      appBar: showAppBar ? AppBar(title: const Text('试验性功能')) : null,
      body: ListView(
        padding: EdgeInsets.only(
          left: showAppBar ? padding.left : 0,
          right: showAppBar ? padding.right : 0,
          bottom: padding.bottom + 100,
        ),
        children: settings.map((item) => item.widget).toList(),
      ),
    );
  }
}
