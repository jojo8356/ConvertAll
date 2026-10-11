// unit_value_editor.dart, provides a number edit widget.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../model/theme_model.dart';
import '../model/unit_controller.dart';
import 'common_widgets.dart';
import '../l10n/l10n.dart';

class UnitValueEditor extends StatefulWidget {
  final bool isFrom;

  const UnitValueEditor({super.key, required this.isFrom});

  @override
  State<UnitValueEditor> createState() => _UnitValueEditorState();
}

class _UnitValueEditorState extends State<UnitValueEditor> {
  final _editController = TextEditingController();
  late final FocusNode _editorFocusNode;

  @override
  void initState() {
    super.initState();
    final model = Provider.of<UnitController>(context, listen: false);
    _editorFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.tab) {
            // Catch tab key to do a select all in the next tab field.
            model.tabPressFlag = true;
          }
        }
        return KeyEventResult.ignored;
      },
    );
    _editorFocusNode.addListener(() {
      if (_editorFocusNode.hasFocus) {
        if (model.tabPressFlag) {
          _editController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _editController.text.length,
          );
          model.tabPressFlag = false;
        }
        // Disable active editor and active unit in model when this gets focus.
        model.updateCurrentUnit(null, null);
      }
    });
  }

  @override
  void dispose() {
    _editController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = widget.isFrom ? scheme.primary : scheme.tertiary;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 50.0, maxWidth: 400.0),
      child: Consumer<UnitController>(
        builder: (context, model, child) {
          final thisUnit = widget.isFrom ? model.fromUnit : model.toUnit;
          if (model.canConvert) {
            if (widget.isFrom != model.fromValueEntered) {
              _editController.text = model.convertedValue();
            } else if (_editController.text.isEmpty &&
                model.enteredValue != null) {
              _editController.text = model.enteredValue.toString();
            }
          }
          return PanelCard(
            accent: accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: SectionLabel(
                        widget.isFrom
                            ? context.l10n.fromValue
                            : context.l10n.toValue,
                      ),
                    ),
                    if (!widget.isFrom)
                      CopyIconButton(
                        text: _editController.text,
                        tooltip: context.l10n.copyTheResult,
                      ),
                  ],
                ),
                const SizedBox(height: AppTheme.gapS),
                ValueField(
                  controller: _editController,
                  focusNode: _editorFocusNode,
                  enabled: model.canConvert,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[\d\.eE\+\-\*/\\(\\) ]'),
                    ),
                  ],
                  onChanged: (String newText) {
                    model.updateEnteredValue(newText, widget.isFrom);
                  },
                ),
                const SizedBox(height: AppTheme.gapS),
                Text(
                  thisUnit.isValid
                      ? thisUnit.toString()
                      : context.l10n.noUnitSet,
                  style: AppTheme.codeText.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
