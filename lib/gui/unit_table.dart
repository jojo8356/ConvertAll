// unit_table.dart, provides a scrollable list of selectable units.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../model/theme_model.dart';
import '../model/unit_controller.dart';
import '../model/unit_data.dart';
import 'common_widgets.dart';

/// Total width of the table, kept in sync with the frame view.
const tableWidth = 750.0;
const nameColWidth = 272.0;
const typeColWidth = 150.0;
const commentColWidth = 296.0;

/// Height of the sticky header and of every row.
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
  Widget build(BuildContext context) {
    return Consumer<UnitController>(
      builder: (context, model, child) {
        final unitList = model.currentPartialMatches();
        if (_vertScrollCtrl.hasClients) {
          final viewHeight =
              _vertScrollCtrl.position.viewportDimension - headerHeight;
          model.tableRowHeight = (viewHeight / lineHeight).floor();
          final visibleUnit =
              model.highlightedTableUnit ?? model.currentUnit?.unitMatch;
          if (visibleUnit != null) {
            final pos = unitList.indexOf(visibleUnit) * lineHeight;
            if (pos >= 0 && pos < _vertScrollCtrl.offset) {
              // Need to scroll up.
              _vertScrollCtrl.jumpTo(pos);
            } else if (pos > _vertScrollCtrl.offset + viewHeight - lineHeight) {
              // Need to scroll down.
              _vertScrollCtrl.jumpTo(pos - viewHeight + lineHeight);
            }
          }
        }
        if (unitList.isEmpty) {
          return SizedBox(
            width: tableWidth,
            height: 170.0,
            child: _emptyState(model),
          );
        }
        // Align and set the max height to get the horizontal scrollbar near
        // the table when there aren't many entries.
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: headerHeight + lineHeight,
              maxHeight:
                  headerHeight +
                  lineHeight *
                      (unitList.isNotEmpty ? unitList.length + 0.3 : 1),
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
                    width: tableWidth,
                    child: CustomScrollView(
                      controller: _vertScrollCtrl,
                      slivers: <Widget>[
                        SliverPersistentHeader(
                          pinned: true,
                          floating: false,
                          delegate: _UnitTableHeader(),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            childCount: unitList.length,
                            (BuildContext context, int index) {
                              final unit = unitList[index];
                              return _UnitRow(
                                unit: unit,
                                isSelected: unit == model.currentUnit?.unitMatch,
                                isActive: unit == model.highlightedTableUnit,
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
  }

  /// Message shown while unit data loads or when a search has no match.
  Widget _emptyState(UnitController model) {
    final isLoading = UnitController.unitData.unitList.isEmpty;
    if (isLoading) {
      return const EmptyState(
        busy: true,
        icon: Icons.storage_rounded,
        title: 'Loading unit data',
        message: 'The unit list is read from the data file at startup.',
      );
    }
    if (model.isFilteringUnitData) {
      return const EmptyState(
        icon: Icons.filter_alt_off_rounded,
        title: 'No units in this category',
        message: 'Use the filter button in the toolbar to show every '
            'category again.',
      );
    }
    return const EmptyState(
      icon: Icons.search_off_rounded,
      title: 'No matching units',
      message: 'Try a shorter search, or clear the field to browse the '
          'full list.',
    );
  }
}

/// One selectable row of the unit list.
class _UnitRow extends StatefulWidget {
  final UnitDatum unit;
  final bool isSelected;
  final bool isActive;
  final VoidCallback onTap;

  const _UnitRow({
    required this.unit,
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
          height: lineHeight,
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
              _cell(widget.unit.nameWithUnabbrev, nameColWidth, style),
              _cell(widget.unit.type, typeColWidth, style),
              _cell(widget.unit.comment, commentColWidth, style),
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

/// Sticky header with the three sortable columns.
class _UnitTableHeader extends SliverPersistentHeaderDelegate {
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
                'Unit name',
                nameColWidth,
              ),
              _headerCell(
                context,
                model,
                SortField.byType,
                'Unit type',
                typeColWidth,
              ),
              _headerCell(
                context,
                model,
                SortField.byComment,
                'Comments',
                commentColWidth,
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
            message: 'Sort by $title',
            child: Padding(
              padding: const EdgeInsets.only(right: 12.0),
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
