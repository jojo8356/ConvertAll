// frame_view.dart, the main view's frame and controls.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../main.dart' show prefs, saveWindowGeo;
import '../model/theme_model.dart';
import '../model/unit_controller.dart';
import 'bases_view.dart';
import 'common_widgets.dart';
import 'fractions_view.dart';
import 'help_view.dart';
import 'settings_edit.dart';
import 'unit_table.dart';
import 'unit_text_editor.dart';
import 'unit_value_editor.dart';
import '../l10n/l10n.dart';

/// Stable side margin once the window is wide enough.
const contentSideMargin = 128.0;

/// Keep the normal margin fixed while preserving the table's minimum width in
/// a compact window.
double contentSideMarginForWidth(double width) {
  return ((width - minimumTableWidth) / 2)
      .clamp(AppTheme.gapL, contentSideMargin)
      .toDouble();
}

/// Space taken by the swap button between the two unit panels.
const _centerGap = 64.0;

class FrameView extends StatefulWidget {
  const FrameView({super.key});

  @override
  State<FrameView> createState() => _FrameViewState();
}

class _FrameViewState extends State<FrameView> with WindowListener {
  // Key is used to avoid focusing open drawer icon.
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  // Stored FocusNode allows explicitly setting focus to from unit on clear.
  final _fromEditorFocusNode = FocusNode();
  String? _version;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      windowManager.addListener(this);
    }
    final model = Provider.of<UnitController>(context, listen: false);
    model.loadData();
    _loadVersion();
    if (prefs.getBool('show_tips') ?? true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        startupTipDialog(context: context);
      });
    }
  }

  /// Read the version shown in the menu header.
  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = packageInfo.version;
      });
    } catch (_) {
      // The version is only decorative, so ignore platforms without it.
    }
  }

  @override
  void dispose() {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  /// Call main function to save window geometry after a resize.
  @override
  void onWindowResize() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      await saveWindowGeo();
    }
  }

  /// Call main function to save window geometry after a move.
  @override
  void onWindowMove() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      await saveWindowGeo();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Size placeholder for hidden icons, includes 8/side padding.
    final iconSize = (IconTheme.of(context).size ?? 24.0) + 16.0;
    return Consumer<UnitController>(
      builder: (context, model, child) {
        return Scaffold(
          key: _scaffoldKey,
          resizeToAvoidBottomInset: true,
          drawer: _buildDrawer(context),
          appBar: AppBar(
            titleSpacing: 0.0,
            title: Row(
              children: <Widget>[
                Image.asset(
                  'assets/images/convertall_icon_48.png',
                  width: 22.0,
                  height: 22.0,
                ),
                const SizedBox(width: AppTheme.gapM),
                const Text('ConvertAll'),
              ],
            ),
            // Manually create button to avoid focus using tab key.
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: context.l10n.menu,
              focusNode: FocusNode(skipTraversal: true),
              onPressed: () => _scaffoldKey.currentState!.openDrawer(),
            ),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.playlist_remove_rounded),
                tooltip: context.l10n.clearUnitEntries,
                focusNode: FocusNode(skipTraversal: true),
                onPressed: () {
                  _fromEditorFocusNode.requestFocus();
                  model.clearUnits();
                },
              ),
              if (!model.isFilteringUnitData) ...<Widget>[
                Focus(
                  // Avoid tab giving focus to this menu.
                  descendantsAreFocusable: false,
                  canRequestFocus: false,
                  descendantsAreTraversable: false,
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.filter_alt),
                    tooltip: context.l10n.filterUnitsByType,
                    onSelected: (result) {
                      model.filterUnitData(result);
                    },
                    itemBuilder: (context) => <PopupMenuEntry<String>>[
                      for (var type in UnitController.unitData.typeList)
                        PopupMenuItem<String>(value: type, child: Text(type)),
                    ],
                  ),
                ),
              ] else ...<Widget>[
                IconButton(
                  icon: const Icon(Icons.filter_alt_off_rounded),
                  tooltip: context.l10n.stopFiltering,
                  focusNode: FocusNode(skipTraversal: true),
                  onPressed: () {
                    model.endFilterUnitData();
                  },
                ),
              ],
              if (model.recentUnits.isNotEmpty &&
                  model.activeEditor != null) ...<Widget>[
                Focus(
                  // Avoid tab giving focus to this menu.
                  descendantsAreFocusable: false,
                  canRequestFocus: false,
                  descendantsAreTraversable: false,
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.history_rounded),
                    tooltip: context.l10n.recentlyUsedUnits,
                    onSelected: (result) {
                      model.replaceCurrentGroup(result);
                    },
                    itemBuilder: (context) => <PopupMenuEntry<String>>[
                      for (var unitText in model.recentUnits)
                        PopupMenuItem<String>(
                          value: unitText,
                          child: Text(unitText),
                        ),
                    ],
                  ),
                ),
              ] else ...<Widget>[
                // Reserve space for hidden recent icon if not present.
                SizedBox(width: iconSize, height: 1.0),
              ],
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sideMargin = contentSideMarginForWidth(
                  constraints.maxWidth,
                );
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    sideMargin,
                    AppTheme.gapL,
                    sideMargin,
                    AppTheme.gapM,
                  ),
                  child: Column(
                    children: <Widget>[
                      _unitsRow(model),
                      const SizedBox(height: AppTheme.gapM),
                      Expanded(child: _tablePanel(context, model)),
                      const SizedBox(height: AppTheme.gapM),
                      _valuesRow(),
                      const SizedBox(height: AppTheme.gapM),
                      _statusBar(context, model),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// The two unit entry panels joined by the swap button.
  Widget _unitsRow(UnitController model) {
    return Row(
      children: <Widget>[
        Expanded(
          child: UnitTextEditor(
            unitGroup: model.fromUnit,
            isFrom: true,
            focusNode: _fromEditorFocusNode,
          ),
        ),
        SizedBox(
          width: _centerGap,
          child: Center(child: _swapButton(context, model)),
        ),
        Expanded(
          child: UnitTextEditor(unitGroup: model.toUnit, isFrom: false),
        ),
      ],
    );
  }

  /// Round button that exchanges the two unit entries.
  Widget _swapButton(BuildContext context, UnitController model) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    return Tooltip(
      message: context.l10n.swapEntries,
      child: Material(
        color: colors.panel,
        shape: CircleBorder(side: BorderSide(color: colors.hairline)),
        child: InkWell(
          customBorder: const CircleBorder(),
          hoverColor: colors.hover,
          onTap: () {
            model.swapUnits();
          },
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Icon(
              Icons.swap_horiz_rounded,
              size: 20.0,
              color: scheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  /// The unit list card with its keyboard hints footer.
  Widget _tablePanel(BuildContext context, UnitController model) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return PanelCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        children: <Widget>[
          const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6.0),
              child: UnitTable(),
            ),
          ),
          Container(
            height: 34.0,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapM),
            decoration: BoxDecoration(
              color: colors.sunkenStrong,
              border: Border(top: BorderSide(color: colors.hairline)),
            ),
            child: Row(
              children: <Widget>[
                KeyHint(keyLabel: '↑ ↓', action: context.l10n.keyBrowse),
                const SizedBox(width: AppTheme.gapL),
                KeyHint(keyLabel: 'Enter', action: context.l10n.keyUseUnit),
                const SizedBox(width: AppTheme.gapL),
                KeyHint(keyLabel: 'Tab', action: context.l10n.keyNextField),
                const Spacer(),
                Flexible(
                  child: Text(
                    model.isFilteringUnitData
                        ? context.l10n.filteredListHint
                        : context.l10n.clickUnitHint,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The two value panels (entered value and converted result).
  Widget _valuesRow() {
    return const Row(
      children: <Widget>[
        Expanded(child: UnitValueEditor(isFrom: true)),
        SizedBox(width: _centerGap),
        Expanded(child: UnitValueEditor(isFrom: false)),
      ],
    );
  }

  /// Feedback bar describing the current conversion state.
  Widget _statusBar(BuildContext context, UnitController model) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final fromValid = model.fromUnit.isValid;
    final toValid = model.toUnit.isValid;
    if (!fromValid && !toValid) {
      return InfoBar(
        icon: Icons.lightbulb_outline_rounded,
        color: scheme.primary,
        message: context.l10n.statusTypeUnit,
      );
    }
    if (fromValid != toValid) {
      return InfoBar(
        icon: Icons.error_outline_rounded,
        color: colors.danger,
        message: context.l10n.statusNotRecognized,
        detail: context.l10n.statusNotRecognizedDetail,
      );
    }
    if (!model.canConvert) {
      final fromReduced = model.fromUnit.reducedGroup?.toString() ?? '';
      final toReduced = model.toUnit.reducedGroup?.toString() ?? '';
      final detail = (fromReduced.isEmpty || toReduced.isEmpty)
          ? null
          : '$fromReduced   ↔   $toReduced';
      return InfoBar(
        icon: Icons.error_outline_rounded,
        color: colors.danger,
        message: context.l10n.statusDifferentUnits,
        detail: detail,
      );
    }
    final reduced = model.fromUnit.reducedGroup?.toString() ?? '';
    return InfoBar(
      icon: Icons.check_circle_outline_rounded,
      color: colors.success,
      message: context.l10n.statusCompatible,
      detail: reduced.isEmpty ? null : context.l10n.reduceTo(reduced),
    );
  }

  /// Side menu with the tools, the help pages and the app version.
  Widget _buildDrawer(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20.0, 22.0, 20.0, 18.0),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 46.0,
                    height: 46.0,
                    padding: const EdgeInsets.all(7.0),
                    decoration: BoxDecoration(
                      color: colors.accentSoft,
                      borderRadius: BorderRadius.circular(14.0),
                    ),
                    child: Image.asset('assets/images/convertall_icon_48.png'),
                  ),
                  const SizedBox(width: AppTheme.gapM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('ConvertAll', style: theme.textTheme.titleLarge),
                        Text(
                          _version == null
                              ? context.l10n.appSubtitle
                              : context.l10n.versionLabel(_version!),
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: colors.hairline, height: 1.0),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8.0, 14.0, 8.0, 14.0),
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 8.0),
                    child: SectionLabel(context.l10n.sectionConversionTools),
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.settings_outlined,
                    label: context.l10n.settingsTitle,
                    hint: context.l10n.settingsHint,
                    onTap: () async {
                      Navigator.pop(context);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingEdit(),
                        ),
                      );
                    },
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.numbers_rounded,
                    label: context.l10n.basesTitle,
                    hint: context.l10n.basesHint,
                    onTap: () async {
                      Navigator.pop(context);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const BasesView(),
                        ),
                      );
                    },
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.pie_chart_rounded,
                    label: context.l10n.fractionsTitle,
                    hint: context.l10n.fractionsHint,
                    onTap: () async {
                      Navigator.pop(context);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const FractionsView(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppTheme.gapS),
                  Padding(
                    padding: EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 8.0),
                    child: SectionLabel(context.l10n.sectionHelp),
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.help_outline_rounded,
                    label: context.l10n.helpViewTitle,
                    onTap: () async {
                      Navigator.pop(context);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const HelpView(),
                        ),
                      );
                    },
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.info_outline_rounded,
                    label: context.l10n.aboutTitle,
                    onTap: () async {
                      Navigator.pop(context);
                      final packageInfo = await PackageInfo.fromPlatform();
                      // Check for an async gap by making sure context is valid.
                      if (!context.mounted) return;
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AboutDialog(
                            applicationName: 'ConvertAll',
                            applicationVersion:
                                context.l10n.versionLabel(packageInfo.version),
                            applicationLegalese: context.l10n.aboutLegalese,
                            applicationIcon: Image.asset(
                              'assets/images/convertall_icon_48.png',
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            if (isDesktop) ...<Widget>[
              Divider(color: colors.hairline, height: 1.0),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: _drawerItem(
                  context,
                  icon: Icons.highlight_off_outlined,
                  label: context.l10n.quit,
                  onTap: () {
                    SystemNavigator.pop();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One entry of the side menu.
  Widget _drawerItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? hint,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
        leading: Icon(icon, size: 19.0),
        title: Text(label, style: theme.textTheme.bodyMedium),
        subtitle: hint == null
            ? null
            : Text(hint, style: theme.textTheme.bodySmall),
        onTap: onTap,
      ),
    );
  }
}
