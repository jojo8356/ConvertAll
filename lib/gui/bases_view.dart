// bases_view.dart, shows a converter between numbers with different bases.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinbox/flutter_spinbox.dart';
import '../model/theme_model.dart';
import 'common_widgets.dart';
import '../l10n/l10n.dart';

typedef ValueBaseCallback = void Function(String entry, int base);

/// Used to store bit depth and two's complement parameters.
class BaseParams {
  final int numBits;
  final bool useTwosComplement;

  BaseParams({this.numBits = 32, this.useTwosComplement = false});

  @override
  String toString() {
    return "$numBits bits, ${useTwosComplement ? '' : 'no '}two's complement";
  }
}

/// Provides a view for base conversions.
class BasesView extends StatefulWidget {
  const BasesView({super.key});

  @override
  State<BasesView> createState() => _BasesViewState();
}

class _BasesViewState extends State<BasesView> {
  int? decValue;
  int? enteredBase;
  var baseParams = BaseParams();
  var errorMsg = '';

  /// Callback to set decimal value and active base.
  void valueBaseChanged(BuildContext context, String entry, int base) {
    entry = entry.replaceAll(' ', '');
    setState(() {
      decValue = _baseInt(entry, base, baseParams);
      enteredBase = base;
      errorMsg = '';
      if (decValue == null && entry.isNotEmpty && entry != '-') {
        errorMsg = context.l10n.invalidEntry;
      }
      if (decValue != null && _baseIsOverflow(decValue!, baseParams)) {
        errorMsg = 'overflow';
        decValue = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.baseConversionsTitle),
        leading: IconButton(
          // Manually create button to avoid focus using tab key.
          icon: const BackButtonIcon(),
          tooltip: context.l10n.back,
          focusNode: FocusNode(skipTraversal: true),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480.0),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.gapL,
              AppTheme.gapL,
              AppTheme.gapL,
              AppTheme.gapXl,
            ),
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconBadge(icon: Icons.numbers_rounded, color: scheme.primary),
                  const SizedBox(width: AppTheme.gapM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SectionLabel(context.l10n.numberBases),
                        const SizedBox(height: 3.0),
                        Text(
                          context.l10n.numberBasesHelp,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.gapM),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  focusNode: FocusNode(skipTraversal: true),
                  icon: const Icon(Icons.tune_rounded, size: 18.0),
                  label: Text(
                    context.l10n.bitDepthValue(baseParams.toString()),
                  ),
                  onPressed: () async {
                    final params = await _baseParamDialog(
                      context: context,
                      initParams: baseParams,
                    );
                    if (params != null) {
                      setState(() {
                        enteredBase = null;
                        baseParams = params;
                        if (decValue != null &&
                            _baseIsOverflow(decValue!, baseParams)) {
                          decValue = null;
                        }
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: AppTheme.gapL),
              PanelCard(
                child: Column(
                  children: <Widget>[
                    BaseEditor(
                      base: 10,
                      label: context.l10n.decimalLabel,
                      regExpStr: r'[\d\-]',
                      isValueFixed: enteredBase == 10,
                      value: decValue,
                      baseParams: baseParams,
                      errorMsg: errorMsg,
                      callback: (String entry, int base) =>
                          valueBaseChanged(context, entry, base),
                    ),
                    const SizedBox(height: AppTheme.gapL),
                    BaseEditor(
                      base: 16,
                      label: context.l10n.hexLabel,
                      regExpStr: r'[\dA-Fa-f\-]',
                      isValueFixed: enteredBase == 16,
                      value: decValue,
                      baseParams: baseParams,
                      errorMsg: errorMsg,
                      callback: (String entry, int base) =>
                          valueBaseChanged(context, entry, base),
                    ),
                    const SizedBox(height: AppTheme.gapL),
                    BaseEditor(
                      base: 8,
                      label: context.l10n.octalLabel,
                      regExpStr: r'[0-7\-]',
                      isValueFixed: enteredBase == 8,
                      value: decValue,
                      baseParams: baseParams,
                      errorMsg: errorMsg,
                      callback: (String entry, int base) =>
                          valueBaseChanged(context, entry, base),
                    ),
                    const SizedBox(height: AppTheme.gapL),
                    BaseEditor(
                      base: 2,
                      label: context.l10n.binaryLabel,
                      regExpStr: r'[01\-]',
                      isValueFixed: enteredBase == 2,
                      value: decValue,
                      baseParams: baseParams,
                      errorMsg: errorMsg,
                      callback: (String entry, int base) =>
                          valueBaseChanged(context, entry, base),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Class for the entry editor for each base.
class BaseEditor extends StatefulWidget {
  final int base;
  final String label;
  final String regExpStr;
  final bool isValueFixed;
  final int? value;
  final BaseParams baseParams;
  final String errorMsg;
  final ValueBaseCallback callback;

  const BaseEditor({
    super.key,
    required this.base,
    required this.label,
    required this.regExpStr,
    required this.isValueFixed,
    required this.value,
    required this.baseParams,
    required this.errorMsg,
    required this.callback,
  });

  @override
  State<BaseEditor> createState() => _BaseEditorState();
}

class _BaseEditorState extends State<BaseEditor> {
  final _editController = TextEditingController();
  late final FocusNode _editorFocusNode;
  static bool tabPressFlag = false;

  @override
  void initState() {
    super.initState();
    _editorFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.tab) {
            // Catch tab key to do a select all in the next tab field.
            _BaseEditorState.tabPressFlag = true;
          }
        }
        return KeyEventResult.ignored;
      },
    );
    _editorFocusNode.addListener(() {
      if (_editorFocusNode.hasFocus) {
        if (_BaseEditorState.tabPressFlag) {
          _editController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _editController.text.length,
          );
          _BaseEditorState.tabPressFlag = false;
        }
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
    if (!widget.isValueFixed) {
      if (widget.value != null) {
        _editController.text = _baseStr(
          widget.value!,
          widget.base,
          widget.baseParams,
        );
      } else {
        _editController.text = '';
      }
    }
    return LabelledTextEditor(
      labelText: context.l10n.baseLabel(widget.label, widget.base),
      errorText: widget.isValueFixed && widget.errorMsg.isNotEmpty
          ? widget.errorMsg
          : null,
      // helperText avoids movement when errorText is shown.
      helperText: ' ',
      style: AppTheme.unitText,
      controller: _editController,
      focusNode: _editorFocusNode,
      autofocus: true,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(widget.regExpStr)),
      ],
      onChanged: (String newText) {
        widget.callback(newText, widget.base);
      },
    );
  }
}

/// Convert a string in the given base/radix to an integer.
///
/// Return null on invalid entry, but does not check for overflow.
int? _baseInt(String baseStr, int base, BaseParams baseParams) {
  final numBits = baseParams.numBits;
  var result = int.tryParse(baseStr, radix: base);
  if (baseParams.useTwosComplement &&
      base != 10 &&
      result != null &&
      result > math.pow(2, numBits - 1) &&
      result < math.pow(2, numBits)) {
    result = result - math.pow(2, numBits).round();
  }
  return result;
}

/// Return true if the given value will overflow.
bool _baseIsOverflow(int value, BaseParams baseParams) {
  final numBits = baseParams.numBits;
  if (baseParams.useTwosComplement) {
    return value >= math.pow(2, numBits - 1) ||
        value < math.pow(-2, numBits - 1);
  } else {
    return value.abs() >= math.pow(2, numBits);
  }
}

/// Return a string representing the value in the given base.
///
/// Does not check for overflow.
String _baseStr(int value, int base, BaseParams baseParams) {
  if (value == 0) return '0';
  final numBits = baseParams.numBits;
  final allDigits = '0123456789abcdef'.split('');
  final resultDigits = <String>[];
  var sign = '';
  if (value < 0) {
    if (baseParams.useTwosComplement && base != 10) {
      value += math.pow(2, numBits).round();
    } else {
      value = value.abs();
      sign = '-';
    }
  }
  while (value > 0) {
    resultDigits.insert(0, allDigits[value % base]);
    value = value ~/ base;
  }
  return '$sign${resultDigits.join('')}';
}

Future<BaseParams?> _baseParamDialog({
  required BuildContext context,
  required BaseParams initParams,
}) async {
  var currentBits = initParams.numBits;
  var currentTwosComplement = initParams.useTwosComplement;
  return showDialog<BaseParams>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text(context.l10n.baseParamsTitle),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionLabel(context.l10n.bitDepth),
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 18.0),
                  child: SpinBox(
                    min: 1.0,
                    max: 256.0,
                    pageStep: 16.0,
                    value: initParams.numBits.toDouble(),
                    onChanged: (double value) {
                      currentBits = value.round();
                    },
                    decoration: InputDecoration(
                      labelText: context.l10n.numberOfBits,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(10.0),
                  onTap: () {
                    setState(() {
                      currentTwosComplement = !currentTwosComplement;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 6.0,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                "Use two's complement",
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                context.l10n.twosComplementHelp,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppTheme.gapM),
                        Switch(
                          value: currentTwosComplement,
                          onChanged: (bool value) {
                            setState(() {
                              currentTwosComplement = !currentTwosComplement;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                context,
                BaseParams(
                  numBits: currentBits,
                  useTwosComplement: currentTwosComplement,
                ),
              );
            },
            child: Text(context.l10n.apply),
          ),
        ],
      );
    },
  );
}
