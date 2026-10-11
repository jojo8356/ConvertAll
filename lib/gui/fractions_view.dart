// fractions_view.dart, shows a converter for fractional numbers.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.

import 'package:async/async.dart';
import 'package:eval_ex/expression.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../model/theme_model.dart';
import 'common_widgets.dart';
import '../l10n/l10n.dart';

const fullWidth = 460.0;
const columnWidth = 220.0;
const headerHeight = 40.0;
const lineHeight = 30.0;

/// Provides a view to do fraction conversions.
class FractionsView extends StatefulWidget {
  const FractionsView({super.key});

  @override
  State<FractionsView> createState() => _FractionsViewState();
}

class _FractionsViewState extends State<FractionsView> {
  var usePowerOfTwo = false;
  final results = <Fraction>[];
  double? decimalValue;
  String? errorText;
  CancelableOperation? _calcOper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.fractionConversionsTitle),
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
          constraints: const BoxConstraints(maxWidth: 520.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.gapL,
              AppTheme.gapL,
              AppTheme.gapL,
              AppTheme.gapL,
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IconBadge(
                      icon: Icons.pie_chart_rounded,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: AppTheme.gapM),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SectionLabel(context.l10n.fractionFinder),
                          const SizedBox(height: 3.0),
                          Text(
                            context.l10n.fractionFinderHelp,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.gapL),
                PanelCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: SectionLabel(context.l10n.valueToConvert),
                          ),
                          Tooltip(
                            message: context.l10n.powersOfTwoTooltip,
                            child: FilterChip(
                              selected: usePowerOfTwo,
                              label: Text(context.l10n.powersOfTwo),
                              onSelected: (bool value) {
                                usePowerOfTwo = value;
                                asyncResults();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.gapM),
                      LabelledTextEditor(
                        labelText: context.l10n.expression,
                        showLabel: false,
                        hintText: context.l10n.expressionHint,
                        style: AppTheme.valueText,
                        errorText: errorText,
                        // helperText avoids movement when errorText is shown.
                        helperText: ' ',
                        autofocus: true,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[\d\.eE\+\-\*/\\(\\) ]'),
                          ),
                        ],
                        onChanged: (String newText) {
                          if (_calcOper != null) {
                            _calcOper!.cancel();
                          }
                          decimalValue = null;
                          errorText = null;
                          if (newText.isNotEmpty) {
                            try {
                              final decimal = Expression(newText).eval();
                              decimalValue = decimal?.toDouble();
                            } on ExpressionException {
                              // Ignore errors, since will check for null value.
                            } on FormatException {
                              // Ignore errors, since will check for null value.
                            }
                            if (decimalValue == null) {
                              errorText = context.l10n.invalidValue;
                            }
                          }
                          asyncResults();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTheme.gapL),
                Expanded(
                  child: PanelCard(
                    padding: EdgeInsets.zero,
                    clip: true,
                    child: FractionTable(results: results),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Calculate fractions and update as an async cancellable operation.
  void asyncResults() {
    results.clear();
    setState(() {});
    if (decimalValue != null) {
      // Start post-frame to allow editor to update first.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _calcOper =
            CancelableOperation.fromFuture(
              fractionResults(decimalValue!, powerOfTwo: usePowerOfTwo),
            ).then((calcResults) {
              results.addAll(calcResults);
              setState(() {});
            });
      });
    }
  }
}

/// Provides a GUI scrolling table to display the fraction results.
class FractionTable extends StatefulWidget {
  final List<Fraction> results;

  const FractionTable({super.key, required this.results});

  @override
  State<FractionTable> createState() => _FractionTableState();
}

class _FractionTableState extends State<FractionTable> {
  final _vertScrollCtrl = ScrollController();
  final _horziScrollCtrl = ScrollController();

  @override
  Widget build(BuildContext context) {
    if (widget.results.isEmpty) {
      return EmptyState(
        icon: Icons.pie_chart_rounded,
        title: context.l10n.noResultTitle,
        message: context.l10n.noResultMessage,
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: headerHeight + lineHeight,
          maxHeight:
              headerHeight +
              lineHeight *
                  (widget.results.isNotEmpty ? widget.results.length + 0.3 : 1),
        ),
        child: Scrollbar(
          controller: _horziScrollCtrl,
          thumbVisibility: true,
          trackVisibility: true,
          child: Scrollbar(
            controller: _vertScrollCtrl,
            thumbVisibility: true,
            trackVisibility: true,
            notificationPredicate: (notif) => notif.depth == 1,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _horziScrollCtrl,
              child: SizedBox(
                width: fullWidth,
                child: CustomScrollView(
                  controller: _vertScrollCtrl,
                  slivers: <Widget>[
                    SliverPersistentHeader(
                      pinned: true,
                      floating: false,
                      delegate: _FractionTableHeader(
                        Localizations.localeOf(context),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        childCount: widget.results.length,
                        (BuildContext context, int index) {
                          return _FractionRow(result: widget.results[index]);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One result row of the fraction table.
class _FractionRow extends StatefulWidget {
  final Fraction result;

  const _FractionRow({required this.result});

  @override
  State<_FractionRow> createState() => _FractionRowState();
}

class _FractionRowState extends State<_FractionRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      fontFeatures: AppTheme.valueText.fontFeatures,
    );
    return MouseRegion(
      onEnter: (event) {
        setState(() {
          _hovered = true;
        });
      },
      onExit: (event) {
        setState(() {
          _hovered = false;
        });
      },
      child: Container(
        height: lineHeight,
        decoration: BoxDecoration(
          color: _hovered ? colors.hover : Colors.transparent,
          border: Border(bottom: BorderSide(color: colors.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(width: 12.0),
            _cell(widget.result.toString(), style),
            _cell(widget.result.toDecimal(), style),
          ],
        ),
      ),
    );
  }

  Widget _cell(String text, TextStyle? style) {
    return SizedBox(
      width: columnWidth,
      child: Padding(
        padding: const EdgeInsets.only(right: 12.0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Provides the result table header.
class _FractionTableHeader extends SliverPersistentHeaderDelegate {
  const _FractionTableHeader(this.locale);

  /// The interface language, used to rebuild the header when it changes.
  final Locale locale;

  @override
  double get maxExtent => headerHeight;

  @override
  double get minExtent => headerHeight;

  @override
  bool shouldRebuild(_FractionTableHeader oldDelegate) =>
      locale != oldDelegate.locale;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = AppColors.of(context);
    final style = AppTheme.overline.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Container(
      height: headerHeight,
      color: colors.sunkenStrong,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(width: 12.0),
          _headerCell(context.l10n.fractionColumn, style),
          _headerCell(context.l10n.decimalLabel, style),
        ],
      ),
    );
  }

  Widget _headerCell(String title, TextStyle style) {
    return SizedBox(
      width: columnWidth,
      child: Padding(
        padding: const EdgeInsets.only(right: 12.0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title.toUpperCase(),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// storage for fraction results.
class Fraction {
  final int numerator;
  final int denominator;

  Fraction(this.numerator, this.denominator);

  @override
  String toString() => '$numerator/$denominator';

  String toDecimal() => (numerator / denominator).toString();
}

/// Return fractions that closely match the given decimal.
Future<List<Fraction>> fractionResults(
  double decimal, {
  var powerOfTwo = false,
}) async {
  final results = <Fraction>[];
  if (decimal == 0.0) return results;
  const denomLimit = 1.0E+9;
  const minOffset = 1.0E-15;
  var denom = 2;
  var numer = (decimal * denom).round();
  var delta = (decimal - numer / denom).abs();
  var minDelta = denomLimit;
  while (denom < denomLimit) {
    final nextDenom = powerOfTwo ? denom * 2 : denom + 1;
    final nextNumer = (decimal * nextDenom).round();
    final nextDelta = (decimal - nextNumer / nextDenom).abs();
    if (numer != 0 &&
        (delta == 0.0 ||
            (delta < minDelta - minOffset && delta <= nextDelta))) {
      results.add(Fraction(numer, denom));
      if (delta < 5.0E-16) break;
      minDelta = delta;
    }
    numer = nextNumer;
    denom = nextDenom;
    delta = nextDelta;
  }
  // Handle case when first result is a whole number (2/2, 4/2, etc.).
  if (results.isNotEmpty) {
    numer = results[0].numerator;
    denom = results[0].denominator;
    if (denom == 2 && numer / denom == (numer / denom).round()) {
      results[0] = Fraction((numer / denom).round(), 1);
    }
  }
  return results;
}
