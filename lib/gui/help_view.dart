// help_view.dart, shows Markdown output of the README file and startup tips.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_selectionarea/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart' show prefs;
import '../model/theme_model.dart';
import 'common_widgets.dart';
import '../l10n/l10n.dart';

const pathPrefix = 'assets/help/';

/// The path of a help page for the given [locale].
String helpPagePath(Locale locale, String page) {
  return locale.languageCode == 'en'
      ? '$pathPrefix$page'
      : '$pathPrefix${locale.languageCode}/$page';
}

/// Provides a view with Markdown output of the README file.
class HelpView extends StatefulWidget {
  const HelpView({super.key});

  @override
  State<HelpView> createState() => _HelpViewState();
}

class _HelpViewState extends State<HelpView> {
  static final _pageHistory = <String>['contents.md'];
  static final _pageList = <String>[];
  String _currentContent = '';
  String? _loadedLanguage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload the page when the app language changes.
    final language = Localizations.localeOf(context).languageCode;
    if (_loadedLanguage != language) {
      _loadedLanguage = language;
      _loadContent();
    }
  }

  void _loadContent() async {
    _currentContent = await rootBundle.loadString(
      helpPagePath(Localizations.localeOf(context), _pageHistory.last),
    );
    // Initialize _pageList once with link addresses from contents page.
    if (_pageList.isEmpty) {
      for (var match in RegExp(r'\[.+\]\((.+)\)').allMatches(_currentContent)) {
        _pageList.add(match.group(1)!);
      }
    }
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pagePos = _pageList.indexOf(_pageHistory.last);
    // Size placeholder for hidden icons, includes 8/side padding.
    final iconSize = (IconTheme.of(context).size ?? 24.0) + 16.0;
    return PopScope(
      canPop: _pageHistory.length <= 1,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop) {
          _pageHistory.removeLast();
          _loadContent();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.helpTitle),
          actions: <Widget>[
            if (pagePos > 0)
              IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                tooltip: context.l10n.previous,
                onPressed: () {
                  _pageHistory.add(_pageList[pagePos - 1]);
                  _loadContent();
                },
              ),
            if (pagePos >= 0 && pagePos < _pageList.length - 1) ...<Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios),
                tooltip: context.l10n.next,
                onPressed: () {
                  _pageHistory.add(_pageList[pagePos + 1]);
                  _loadContent();
                },
              ),
            ] else ...<Widget>[
              SizedBox(width: iconSize, height: 1.0),
            ],
            if (_pageHistory.last != _pageHistory.first) ...<Widget>[
              IconButton(
                icon: const Icon(Icons.home_outlined),
                tooltip: context.l10n.home,
                onPressed: () {
                  _pageHistory.add(_pageHistory.first);
                  _loadContent();
                },
              ),
            ] else ...<Widget>[
              SizedBox(width: iconSize, height: 1.0),
            ],
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: context.l10n.close,
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780.0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.gapL,
                AppTheme.gapL,
                AppTheme.gapL,
                AppTheme.gapL,
              ),
              child: PanelCard(
                padding: EdgeInsets.zero,
                clip: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.gapXl,
                    AppTheme.gapL,
                    AppTheme.gapXl,
                    AppTheme.gapXl,
                  ),
                  child: SelectionArea(
                    child: Markdown(
                      data: _currentContent,
                      onTapLink: (String text, String? href, String title) async {
                        if (href != null) {
                          if (href.contains(':')) {
                            launchUrl(
                              Uri.parse(href),
                              mode: LaunchMode.externalApplication,
                            );
                          } else if (href.endsWith('.md')) {
                            _pageHistory.add(href);
                            _loadContent();
                          }
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Examples shown in the startup tip dialog.
List<(String, String)> _tipExamples(BuildContext context) => <(String, String)>[
  ('m / s', context.l10n.tipMetersPerSecond),
  ('ft * lbf', context.l10n.tipFootPounds),
  ('in^2', context.l10n.tipSquareInches),
  ('m^3', context.l10n.tipCubicMeters),
];

Future<void> startupTipDialog({required BuildContext context}) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      var showTip = true;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final colors = AppColors.of(context);
      return AlertDialog(
        title: Row(
          children: <Widget>[
            IconBadge(icon: Icons.bolt_rounded, color: scheme.primary),
            const SizedBox(width: AppTheme.gapM),
            Expanded(child: Text(context.l10n.combineAnyUnits)),
          ],
        ),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    context.l10n.startupTipIntro,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppTheme.gapL),
                  for (final example in _tipExamples(context))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                              vertical: 3.0,
                            ),
                            decoration: BoxDecoration(
                              color: colors.sunken,
                              borderRadius: BorderRadius.circular(7.0),
                              border: Border.all(color: colors.hairline),
                            ),
                            child: Text(
                              example.$1,
                              style: AppTheme.codeText.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTheme.gapM),
                          Expanded(
                            child: Text(
                              example.$2,
                              style: theme.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppTheme.gapXs),
                  Divider(color: colors.hairline),
                  InkWell(
                    onTap: () {
                      setState(() {
                        showTip = !showTip;
                        prefs.setBool('show_tips', showTip);
                      });
                    },
                    child: Row(
                      children: <Widget>[
                        Expanded(child: Text(context.l10n.showTipAtStartup)),
                        Switch(
                          value: showTip,
                          onChanged: (bool value) {
                            setState(() {
                              showTip = !showTip;
                              prefs.setBool('show_tips', showTip);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.gotIt),
          ),
        ],
      );
    },
  );
}
