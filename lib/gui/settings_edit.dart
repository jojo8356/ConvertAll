// settings_edit.dart, a view to edit the app's preferences.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../main.dart'
    show prefs, minWidth, minHeight, allowSaveWindowGeo, saveWindowGeo;
import '../model/theme_model.dart';
import '../model/unit_controller.dart';
import 'common_widgets.dart';

/// A user settings view.
class SettingEdit extends StatefulWidget {
  const SettingEdit({super.key});

  @override
  State<SettingEdit> createState() => _SettingEditState();
}

class _SettingEditState extends State<SettingEdit> {
  /// A flag showing that the view was forced to close.
  var _cancelFlag = false;

  final _formKey = GlobalKey<FormState>();
  final origViewScale = prefs.getDouble('view_scale') ?? 1.0;

  /// True on desktop platforms that use the native window manager.
  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Prepare to close by validating and updating.
  ///
  /// Returns true if it's ok to close.
  Future<bool> _handleClose() async {
    if (_cancelFlag) return true;
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final viewScale = prefs.getDouble('view_scale') ?? 1.0;
      if (viewScale != origViewScale && _isDesktop) {
        final currentSize = await windowManager.getSize();
        var currentWidth = currentSize.width;
        var currentHeight = currentSize.height;
        if (currentWidth < minWidth * viewScale) {
          currentWidth = minWidth * viewScale;
        }
        if (currentHeight < minHeight * viewScale) {
          currentHeight = minHeight * viewScale;
        }
        if (currentWidth != currentSize.width ||
            currentHeight != currentSize.height) {
          await windowManager.setSize(Size(currentWidth, currentHeight));
        }
        await windowManager.setMinimumSize(
          Size(minWidth * viewScale, minHeight * viewScale),
        );
      }
      if (!mounted) return true;
      final model = Provider.of<UnitController>(context, listen: false);
      model.generalUpdate();
      final themeModel = Provider.of<ThemeModel>(context, listen: false);
      themeModel.updateTheme();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          // Manually create button to avoid focus using tab key.
          icon: const BackButtonIcon(),
          tooltip: 'Save and go back',
          focusNode: FocusNode(skipTraversal: true),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.check_rounded),
            tooltip: 'Save and close',
            focusNode: FocusNode(skipTraversal: true),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close without saving',
            focusNode: FocusNode(skipTraversal: true),
            onPressed: () {
              _cancelFlag = true;
              Navigator.pop(context, null);
            },
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) async {
          if (didPop) return;
          if (await _handleClose() && context.mounted) {
            // Pop manually (bypass canPop) if update is complete.
            Navigator.of(context).pop();
          }
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500.0),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.gapL,
                AppTheme.gapL,
                AppTheme.gapL,
                AppTheme.gapXl,
              ),
              children: <Widget>[
                const SectionLabel('Number formatting'),
                const SizedBox(height: AppTheme.gapS),
                PanelCard(
                  child: Column(
                    children: <Widget>[
                      DropdownButtonFormField<int>(
                        items: <DropdownMenuItem<int>>[
                          for (var item in NumRepr.values)
                            DropdownMenuItem<int>(
                              value: item.index,
                              child: Text(
                                '${item.name.substring(0, 1).toUpperCase()}'
                                '${item.name.substring(1)}',
                              ),
                            ),
                        ],
                        value: prefs.getInt('result_notation') ?? 0,
                        decoration: const InputDecoration(
                          labelText: 'Result notation',
                          helperText:
                              'How converted values are written (short, '
                              'fixed, scientific or engineering)',
                        ),
                        onChanged: (int? value) {},
                        onSaved: (int? value) async {
                          if (value != null) {
                            await prefs.setInt('result_notation', value);
                          }
                        },
                      ),
                      const SizedBox(height: AppTheme.gapL),
                      TextFormField(
                        initialValue: (prefs.getInt('num_dec_plcs') ?? 8)
                            .toString(),
                        decoration: const InputDecoration(
                          labelText: 'Number of decimal places',
                          helperText: 'Between 0 and 9 digits after the '
                              'decimal point',
                        ),
                        validator: (String? value) {
                          if (value != null && value.isNotEmpty) {
                            var places = int.tryParse(value);
                            if (places == null) {
                              return 'Must be an integer';
                            }
                            if (places < 0 || places > 9) {
                              return 'Must be between 0 and 9';
                            }
                          }
                          return null;
                        },
                        onSaved: (String? value) async {
                          if (value != null && value.isNotEmpty) {
                            await prefs.setInt(
                              'num_dec_plcs',
                              int.parse(value),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.gapXl),
                const SectionLabel('Startup and recent units'),
                const SizedBox(height: AppTheme.gapS),
                PanelCard(
                  child: Column(
                    children: <Widget>[
                      BoolFormField(
                        initialValue: prefs.getBool('load_recent') ?? false,
                        heading: 'Load the most recent units at startup',
                        subheading: 'Restores the last conversion when the app '
                            'opens',
                        onSaved: (bool? value) async {
                          if (value != null) {
                            await prefs.setBool('load_recent', value);
                          }
                        },
                      ),
                      TextFormField(
                        initialValue: (prefs.getInt('recent_unit_count') ?? 12)
                            .toString(),
                        decoration: const InputDecoration(
                          labelText: 'Number of saved recent units',
                          helperText: 'Shown in the recent units menu',
                        ),
                        validator: (String? value) {
                          if (value != null && value.isNotEmpty) {
                            var count = int.tryParse(value);
                            if (count == null) {
                              return 'Must be an integer';
                            }
                            if (count < 0) {
                              return 'Must be greater than or equal to zero';
                            }
                          }
                          return null;
                        },
                        onSaved: (String? value) async {
                          if (value != null && value.isNotEmpty) {
                            var intValue = int.parse(value);
                            await prefs.setInt('recent_unit_count', intValue);
                            if (!context.mounted) return;
                            final model = Provider.of<UnitController>(
                              context,
                              listen: false,
                            );
                            if (model.recentUnits.length > intValue) {
                              model.recentUnits.removeRange(
                                intValue,
                                model.recentUnits.length,
                              );
                            }
                          }
                        },
                      ),
                      const SizedBox(height: AppTheme.gapM),
                      BoolFormField(
                        initialValue: prefs.getBool('show_tips') ?? true,
                        heading: 'Show the tips dialog at startup',
                        subheading: 'Explains how units can be combined',
                        onSaved: (bool? value) async {
                          if (value != null) {
                            await prefs.setBool('show_tips', value);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.gapXl),
                const SectionLabel('Appearance'),
                const SizedBox(height: AppTheme.gapS),
                PanelCard(
                  child: Column(
                    children: <Widget>[
                      BoolFormField(
                        initialValue: prefs.getBool('dark_theme') ?? false,
                        heading: 'Dark theme',
                        subheading: 'Switches the whole interface to the dark '
                            'palette',
                        onSaved: (bool? value) async {
                          if (value != null) {
                            await prefs.setBool('dark_theme', value);
                          }
                        },
                      ),
                      const SizedBox(height: AppTheme.gapL),
                      TextFormField(
                        initialValue: (prefs.getDouble('view_scale') ?? 1.0)
                            .toString(),
                        decoration: const InputDecoration(
                          labelText: 'App view scale ratio',
                          helperText: 'Valid range is 0.25 to 4.0',
                        ),
                        validator: (String? value) {
                          if (value != null && value.isNotEmpty) {
                            final scale = double.tryParse(value);
                            if (scale == null) {
                              return 'Must be an number';
                            }
                            if (scale > 4.0 || scale < 0.25) {
                              return 'Valid range is 0.25 to 4.0';
                            }
                          }
                          return null;
                        },
                        onSaved: (String? value) async {
                          if (value != null && value.isNotEmpty) {
                            await prefs.setDouble(
                              'view_scale',
                              double.parse(value),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                if (_isDesktop) ...<Widget>[
                  const SizedBox(height: AppTheme.gapXl),
                  const SectionLabel('Window'),
                  const SizedBox(height: AppTheme.gapS),
                  PanelCard(
                    child: Column(
                      children: <Widget>[
                        BoolFormField(
                          initialValue:
                              prefs.getBool('save_window_geo') ?? true,
                          heading: 'Remember window position and size',
                          subheading: 'Reopens the window where it was closed',
                          onSaved: (bool? value) async {
                            if (value != null) {
                              await prefs.setBool('save_window_geo', value);
                              allowSaveWindowGeo = value;
                              if (allowSaveWindowGeo) saveWindowGeo();
                            }
                          },
                        ),
                        BoolFormField(
                          initialValue: prefs.getBool('show_title_bar') ?? true,
                          heading: 'Show the window title bar',
                          subheading: 'Turn off for a cleaner look under '
                              'Wayland',
                          onSaved: (bool? value) async {
                            if (value != null) {
                              await prefs.setBool('show_title_bar', value);
                              await windowManager.setTitleBarStyle(
                                value
                                    ? TitleBarStyle.normal
                                    : TitleBarStyle.hidden,
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A [FormField] widget for boolean settings.
class BoolFormField extends FormField<bool> {
  BoolFormField({
    String? heading,
    String? subheading,
    super.initialValue,
    super.key,
    super.onSaved,
  }) : super(
         builder: (FormFieldState<bool> state) {
           final theme = Theme.of(state.context);
           return Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: <Widget>[
               InkWell(
                 borderRadius: BorderRadius.circular(10.0),
                 onTap: () {
                   state.didChange(!state.value!);
                 },
                 child: Padding(
                   padding: const EdgeInsets.symmetric(
                     horizontal: 4.0,
                     vertical: 8.0,
                   ),
                   child: Row(
                     children: <Widget>[
                       Expanded(
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: <Widget>[
                             Text(
                               heading ?? 'Boolean Value',
                               style: theme.textTheme.bodyMedium?.copyWith(
                                 fontWeight: FontWeight.w600,
                               ),
                             ),
                             if (subheading != null)
                               Padding(
                                 padding: const EdgeInsets.only(top: 2.0),
                                 child: Text(
                                   subheading,
                                   style: theme.textTheme.bodySmall,
                                 ),
                               ),
                           ],
                         ),
                       ),
                       const SizedBox(width: AppTheme.gapM),
                       Switch(
                         value: state.value!,
                         onChanged: (bool value) {
                           state.didChange(!state.value!);
                         },
                       ),
                     ],
                   ),
                 ),
               ),
               const Divider(height: 1.0),
             ],
           );
         },
       );
}
