import 'package:convertall/gui/frame_view.dart';
import 'package:convertall/gui/unit_table.dart';
import 'package:convertall/l10n/app_localizations.dart';
import 'package:convertall/model/unit_controller.dart';
import 'package:convertall/model/unit_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  const longComment = 'Manufacturers Std. Gauge, non-linear';

  tearDown(() {
    UnitController.unitData.reset();
  });

  test('wide windows keep fixed margins and give their width to the table', () {
    expect(contentSideMarginForWidth(1000.0), contentSideMargin);
    expect(contentSideMarginForWidth(1500.0), contentSideMargin);
    expect(contentSideMarginForWidth(520.0), 44.0);

    final normalTableWidth = 1000.0 - 2 * contentSideMarginForWidth(1000.0);
    final wideTableWidth = 1500.0 - 2 * contentSideMarginForWidth(1500.0);
    expect(wideTableWidth - normalTableWidth, 500.0);
    expect(normalTableWidth, greaterThanOrEqualTo(minimumTableWidth));
  });

  test('responsive layout gives spare width to the comments column', () {
    final normal = UnitTableLayout.forWidth(tableWidth);
    final wide = UnitTableLayout.forWidth(1000.0);
    final narrow = UnitTableLayout.forWidth(300.0);

    expect(normal.nameWidth, closeTo(nameColWidth, 0.01));
    expect(normal.typeWidth, closeTo(typeColWidth, 0.01));
    expect(normal.commentWidth, closeTo(commentColWidth, 0.01));
    expect(normal.commentWidth, greaterThan(normal.nameWidth));
    expect(normal.commentWidth, greaterThan(normal.width * 0.45));
    expect(wide.commentWidth, greaterThan(normal.commentWidth));
    expect(narrow.width, minimumTableWidth);
    expect(narrow.commentWidth, greaterThanOrEqualTo(165.0));
  });

  test('unit metadata translates types and comments independently', () {
    final item = <String, dynamic>{
      'name': 'versta',
      'type': 'length',
      'equiv': '3500 ft',
      'comment': 'Russian unit',
    };

    translateUnitMetadata(
      item,
      const {'length': 'longueur'},
      const {'Russian unit': 'unité russe'},
    );

    expect(item['name'], 'versta');
    expect(item['type'], 'longueur');
    expect(item['comment'], 'unité russe');
  });

  test('comment height accounts for wrapping and accessible text scaling', () {
    const style = TextStyle(fontSize: 14.0, height: 1.2);
    final wide = unitTableCommentRowHeight(
      longComment,
      width: 800.0,
      style: style,
      textScaler: TextScaler.noScaling,
      textDirection: TextDirection.ltr,
    );
    final narrow = unitTableCommentRowHeight(
      longComment,
      width: 140.0,
      style: style,
      textScaler: TextScaler.noScaling,
      textDirection: TextDirection.ltr,
    );
    final accessible = unitTableCommentRowHeight(
      longComment,
      width: 140.0,
      style: style,
      textScaler: const TextScaler.linear(2.0),
      textDirection: TextDirection.ltr,
    );

    expect(wide, lineHeight);
    expect(narrow, greaterThan(lineHeight));
    expect(accessible, greaterThan(narrow));
  });

  testWidgets('the whole comment remains visible when the table narrows', (
    tester,
  ) async {
    final unit = UnitDatum({
      'name': 'standard gauge',
      'type': 'length',
      'equiv': '1 m',
      'comment': longComment,
    });
    UnitController.unitData.unitList.add(unit);
    UnitController.unitData.unitMap[unit.name] = unit;
    final controller = UnitController();

    Future<void> pumpAtWidth(double width) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<UnitController>.value(
          value: controller,
          child: MaterialApp(
            localizationsDelegates:
                AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  height: 180.0,
                  child: const UnitTable(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpAtWidth(440.0);

    final commentFinder = find.byKey(
      const ValueKey('unit-comment-standard gauge'),
    );
    final rowFinder = find.byKey(const ValueKey('unit-row-standard gauge'));
    final commentWidget = tester.widget<Text>(commentFinder);
    final narrowRowHeight = tester.getSize(rowFinder).height;
    final rowRect = tester.getRect(rowFinder);
    final commentRect = tester.getRect(commentFinder);

    expect(commentWidget.data, longComment);
    expect(commentWidget.maxLines, isNull);
    expect(commentWidget.softWrap, isTrue);
    expect(commentWidget.overflow, TextOverflow.visible);
    expect(narrowRowHeight, greaterThan(lineHeight));
    expect(commentRect.top, greaterThanOrEqualTo(rowRect.top));
    expect(commentRect.bottom, lessThanOrEqualTo(rowRect.bottom));
    expect(tester.takeException(), isNull);

    await pumpAtWidth(900.0);
    final wideRowHeight = tester.getSize(rowFinder).height;

    // The test font can still wrap at 900 logical pixels on some platforms;
    // what matters is that more width reduces the reserved height and no text
    // is clipped.
    expect(wideRowHeight, lessThan(narrowRowHeight));
    expect(tester.takeException(), isNull);
  });
}
