// unit_json.dart, the JSON shape of a unit, shared by the CLI and the MCP server.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The command line `--json` output and the `structuredContent` of the MCP
// tools use the same member names, so that a script and a language model see
// the same thing.  The MCP tools describe this shape in their `outputSchema`
// (see `lib/mcp/mcp_tools.dart`): the members listed as required here are
// always present, the two optional ones only when the data has them.

import 'unit_database.dart';

/// One unit as a JSON object.
///
/// * `name`: the name to use in a conversion;
/// * `type`: the canonical (English) quantity;
/// * `type_display`: the quantity in the display language;
/// * `equivalent`: the unit this one is defined against (`!` for a base unit);
/// * `non_linear`: true when converting needs an equation or a table;
/// * `base_unit`: true for one of the eleven base units;
/// * `unabbrev` (optional): the spelled out name;
/// * `comment` (optional): the note stored with the unit.
Map<String, Object?> unitToJson(UnitRecord unit) => {
  'name': unit.name,
  'type': unit.canonicalType,
  'type_display': unit.displayType,
  'equivalent': unit.equiv,
  'non_linear': unit.isNonLinear,
  'base_unit': unit.isBaseUnit,
  if (unit.unabbrev.isNotEmpty) 'unabbrev': unit.unabbrev,
  if (unit.comment.isNotEmpty) 'comment': unit.comment,
};

/// The JSON of a list of units, in the order given.
List<Map<String, Object?>> unitListToJson(List<UnitRecord> units) =>
    units.map(unitToJson).toList();

/// The JSON of a failed operation: `{"ok": false, "error": ..., ...}`.
///
/// The MCP server does not use this envelope (a failed tool call is reported
/// with `isError: true` and a text block), but the command line does, since a
/// script needs a machine readable reason for the exit status.
Map<String, Object?> errorToJson(
  String message, {
  String? code,
  List<String> suggestions = const [],
}) => {
  'ok': false,
  'error': message,
  if (code != null) 'error_code': code,
  if (suggestions.isNotEmpty) 'suggestions': suggestions,
};
