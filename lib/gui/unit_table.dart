// unit_table.dart, provides a scrollable list of selectable units.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../model/theme_model.dart';
import '../model/unit_controller.dart';
import '../model/unit_data.dart';
import 'common_widgets.dart';
import '../l10n/l10n.dart';

/// Preferred table dimensions at the application's normal window size.
const tableWidth = 750.0;
const minimumTableWidth = 432.0;
const nameColWidth = 230.0;
const typeColWidth = 125.0;
const commentColWidth = 363.0;
const tableTrailingPadding = 20.0;
const cellRightPadding = 12.0;
const cellVerticalPadding = 5.0;

/// Responsive widths shared by the header and every data row.
///
/// At 750 logical pixels comments receive just over half of the usable width.
/// Extra room primarily benefits comments, while a narrow window retains
/// usable minimums for all three columns.
@immutable
class UnitTableLayout {
  final double width;
  final double nameWidth;
  final double typeWidth;
  final double commentWidth;

  const UnitTableLayout._(
    this.width,
    this.nameWidth,
    this.typeWidth,
    this.commentWidth,
  );

  factory UnitTableLayout.forWidth(double availableWidth) {
    final width = availableWidth.isFinite
        ? math.max(minimumTableWidth, availableWidth)
        : tableWidth;
    final columnSpace =
        width - markerWidth - markerGap - tableTrailingPadding;
    const minimumName = 140.0;
    const minimumType = 95.0;
    const minimumComment = 165.0;
    final extra = math.max(0.0, columnSpace - 400.0);
    return UnitTableLayout._(
      width,
      minimumName + extra * (90.0 / 318.0),
      minimumType + extra * (30.0 / 318.0),
      minimumComment + extra * (198.0 / 318.0),
    );
  }
}

/// Height needed to display [comment] completely at [width].
///
/// This is public so widget tests can verify that accessibility text scaling
/// and narrow windows never silently clip a comment.
double unitTableCommentRowHeight(
  String comment, {
  required double width,
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  if (comment.isEmpty) return lineHeight;
  final painter = TextPainter(
    text: TextSpan(text: comment, style: style),
    textScaler: textScaler,
    textDirection: textDirection,
  )..layout(maxWidth: math.max(1.0, width - cellRightPadding));
  return math.max(
    lineHeight,
    (painter.height + cellVerticalPadding * 2).ceilToDouble(),
  );
}

/// Height of the sticky header and minimum height of a data row.
const headerHeight = 40.0;
const lineHeight = 30.0;

/// Width of the selection marker plus its gap inside a row.
const markerWidth = 3.0;
const markerGap = 9.0;

class UnitTable extends StatefulWidget {
  const UnitTable({super.key});

  @override
  State<UnitTable> createState() => _UnitTableState();
}

class _UnitTableState extends State<UnitTable> {
  final _vertScrollCtrl = ScrollController();
  final _horziScrollCtrl = ScrollController();

  @override
  void dispose() {
    _vertScrollCtrl.dispose();
    _horziScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = UnitTableLayout.forWidth(constraints.maxWidth);
        return Consumer<UnitController>(
          builder: (context, model, child) {
            final unitList = model.currentPartialMatches();
            if (unitList.isEmpty) {
              return SizedBox(
                width: layout.width,
                height: 170.0,
                child: _emptyState(context, model),
              );
            }

            // Measure with the bold variant too: selection must never make the
            // last word move into a line that the row did not reserve.
            final rowStyle = (Theme.of(context).textTheme.bodyMedium ??
                    const TextStyle(fontSize: 14.0))
                .copyWith(fontWeight: FontWeight.w600);
            final textScaler = MediaQuery.textScalerOf(context);
            final textDirection = Directionality.of(context);
            final rowHeights = <double>[];
            final rowOffsets = <double>[0.0];
            for (final unit in unitList) {
              final height = unitTableCommentRowHeight(
                unit.comment,
                width: layout.commentWidth,
                style: rowStyle,
                textScaler: textScaler,
                textDirection: textDirection,
              );
              rowHeights.add(height);
              rowOffsets.add(rowOffsets.last + height);
            }

            if (_vertScrollCtrl.hasClients) {
              final viewHeight = math.max(
                lineHeight,
                _vertScrollCtrl.position.viewportDimension - headerHeight,
              );
              final averageHeight = rowOffsets.last / unitList.length;
              model.tableRowHeight = math.max(
                1,
                (viewHeight / averageHeight).floor(),
              );
              final visibleUnit =
                  model.highlightedTableUnit ?? model.currentUnit?.unitMatch;
              final index = visibleUnit == null
                  ? -1
                  : unitList.indexOf(visibleUnit);
              if (index >= 0) {
                final top = rowOffsets[index];
                final bottom = rowOffsets[index + 1];
                if (top < _vertScrollCtrl.offset) {
                  _vertScrollCtrl.jumpTo(top);
                } else if (bottom > _vertScrollCtrl.offset + viewHeight) {
                  _vertScrollCtrl.jumpTo(bottom - viewHeight);
                }
              }
            }

            // Align and keep the horizontal scrollbar close to short lists.
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: headerHeight + lineHeight,
                  maxHeight: headerHeight + rowOffsets.last + lineHeight * 0.3,
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
                        width: layout.width,
                        child: CustomScrollView(
                          controller: _vertScrollCtrl,
                          slivers: <Widget>[
                            SliverPersistentHeader(
                              pinned: true,
                              floating: false,
                              delegate: _UnitTableHeader(layout),
                            ),
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                childCount: unitList.length,
                                (BuildContext context, int index) {
                                  final unit = unitList[index];
                                  return _UnitRow(
                                    key: ValueKey('unit-row-${unit.name}'),
                                    unit: unit,
                                    layout: layout,
                                    height: rowHeights[index],
                                    isSelected:
                                        unit == model.currentUnit?.unitMatch,
                                    isActive:
                                        unit == model.highlightedTableUnit,
                                    onTap: () {
                                      model.replaceCurrentUnit(unit);
                                    },
                                  );
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
          },
        );
      },
    );
  }

  /// Message shown while unit data loads or when a search has no match.
  Widget _emptyState(BuildContext context, UnitController model) {
    final isLoading = UnitController.unitData.unitList.isEmpty;
    if (isLoading) {
      return EmptyState(
        busy: true,
        icon: Icons.storage_rounded,
        title: context.l10n.loadingUnitsTitle,
        message: context.l10n.loadingUnitsMessage,
      );
    }
    if (model.isFilteringUnitData) {
      return EmptyState(
        icon: Icons.filter_alt_off_rounded,
        title: context.l10n.noUnitsInCategoryTitle,
        message: context.l10n.noUnitsInCategoryMessage,
      );
    }
    return EmptyState(
      icon: Icons.search_off_rounded,
      title: context.l10n.noMatchingUnitsTitle,
      message: context.l10n.noMatchingUnitsMessage,
    );
  }
}

/// One selectable row of the unit list.
class _UnitRow extends StatefulWidget {
  final UnitDatum unit;
  final UnitTableLayout layout;
  final double height;
  final bool isSelected;
  final bool isActive;
  final VoidCallback onTap;

  const _UnitRow({
    super.key,
    required this.unit,
    required this.layout,
    required this.height,
    required this.isSelected,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_UnitRow> createState() => _UnitRowState();
}

class _UnitRowState extends State<_UnitRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);
    final Color background;
    final Color textColor;
    if (widget.isSelected) {
      background = scheme.primaryContainer;
      textColor = scheme.onPrimaryContainer;
    } else if (widget.isActive) {
      background = colors.highlight;
      textColor = scheme.primary;
    } else {
      background = _hovered ? colors.hover : Colors.transparent;
      textColor = scheme.onSurface;
    }
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: textColor,
      fontWeight: widget.isSelected || widget.isActive
          ? FontWeight.w600
          : FontWeight.w400,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
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
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: background,
            border: Border(bottom: BorderSide(color: colors.hairline)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                width: markerWidth,
                color: widget.isSelected ? scheme.primary : Colors.transparent,
              ),
              const SizedBox(width: markerGap),
              _cell(
                widget.unit.nameWithUnabbrev,
                widget.layout.nameWidth,
                style,
              ),
              _cell(widget.unit.type, widget.layout.typeWidth, style),
              _commentCell(
                widget.unit.comment,
                widget.layout.commentWidth,
                style,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(String text, double width, TextStyle? style) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(right: cellRightPadding),
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

  Widget _commentCell(String text, double width, TextStyle? style) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(
          right: cellRightPadding,
          top: cellVerticalPadding,
          bottom: cellVerticalPadding,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            key: ValueKey('unit-comment-${widget.unit.name}'),
            style: style,
            softWrap: true,
            overflow: TextOverflow.visible,
          ),
        ),
      ),
    );
  }
}

/// Sticky header with the three sortable columns.
class _UnitTableHeader extends SliverPersistentHeaderDelegate {
  final UnitTableLayout layout;

  const _UnitTableHeader(this.layout);

  @override
  double get maxExtent => headerHeight;

  @override
  double get minExtent => headerHeight;

  // Rebuild is needed to update the sort direction and the light/dark theme.
  @override
  bool shouldRebuild(_UnitTableHeader oldDelegate) => true;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = AppColors.of(context);
    return Consumer<UnitController>(
      builder: (context, model, child) {
        return Container(
          height: headerHeight,
          color: colors.sunkenStrong,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(width: markerWidth + markerGap),
              _headerCell(
                context,
                model,
                SortField.byName,
                context.l10n.columnUnitName,
                layout.nameWidth,
              ),
              _headerCell(
                context,
                model,
                SortField.byType,
                context.l10n.columnUnitType,
                layout.typeWidth,
              ),
              _headerCell(
                context,
                model,
                SortField.byComment,
                context.l10n.columnComments,
                layout.commentWidth,
              ),
            ],
          ),
        );
      },
    );
  }

  /// One clickable column title with its sort indicator.
  Widget _headerCell(
    BuildContext context,
    UnitController model,
    SortField field,
    String title,
    double width,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isSorted = model.sortParam.sortField == field;
    final style = AppTheme.overline.copyWith(
      color: isSorted ? scheme.primary : scheme.onSurfaceVariant,
    );
    return SizedBox(
      width: width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            model.handleHeaderTap(field);
          },
          child: Tooltip(
            message: context.l10n.sortByTitle(title),
            child: Padding(
              padding: const EdgeInsets.only(right: cellRightPadding),
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      title.toUpperCase(),
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  Icon(
                    !isSorted
                        ? Icons.unfold_more_rounded
                        : (model.sortParam.sortForward
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded),
                    size: 14.0,
                    color: isSorted ? scheme.primary : scheme.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
