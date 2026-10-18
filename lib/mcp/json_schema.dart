// json_schema.dart, a small JSON Schema validator for tool arguments.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The MCP specification requires a server to validate every tool input
// ("Servers MUST validate all tool inputs", tools page of the 2026-07-28
// revision).  Only the keywords used by the schemas declared in
// `mcp_tools.dart` are implemented; anything else is ignored, so adding a
// keyword to a schema never breaks an input that used to be accepted.

import 'dart:convert' show jsonEncode;

/// Validates JSON values against a JSON Schema, with a readable message.
class JsonSchemaValidator {
  JsonSchemaValidator(Object? schema)
    : schema = schema is Map ? schema.cast<String, Object?>() : const {};

  /// The schema to validate against.
  final Map<String, Object?> schema;

  /// Return an error message, or `null` when [value] is valid.
  ///
  /// The message names the member at fault in plain words, e.g.
  /// `the member "limit": 1000 is above the maximum of 200.`, so that a model
  /// reading it can correct its call.
  String? validate(Object? value) => _check(value, schema, 'the arguments');

  /// A copy of [arguments] with the `default` values of the schema applied to
  /// the members that are absent.
  Map<String, Object?> withDefaults(Map<String, Object?> arguments) {
    final result = Map<String, Object?>.of(arguments);
    final properties = schema['properties'];
    if (properties is Map) {
      properties.forEach((key, propertySchema) {
        if (key is! String || propertySchema is! Map) return;
        if (result.containsKey(key)) return;
        final defaultValue = propertySchema['default'];
        if (defaultValue != null) result[key] = defaultValue;
      });
    }
    return result;
  }

  String? _check(Object? value, Map<String, Object?> schema, String path) {
    final types = _typesOf(schema['type']);
    if (types != null && !types.any((type) => _matchesType(value, type))) {
      return '$path: expected ${_join(types)}, got ${_describe(value)}.';
    }
    final allowed = schema['enum'];
    if (allowed is List && !allowed.any((candidate) => _sameValue(candidate, value))) {
      return '$path: expected one of ${allowed.map(_literal).join(', ')}, '
          'got ${_literal(value)}.';
    }
    if (value is num) {
      final minimum = schema['minimum'];
      if (minimum is num && value < minimum) {
        return '$path: $value is below the minimum of $minimum.';
      }
      final maximum = schema['maximum'];
      if (maximum is num && value > maximum) {
        return '$path: $value is above the maximum of $maximum.';
      }
    }
    if (value is String) {
      final minLength = schema['minLength'];
      if (minLength is int && value.length < minLength) {
        return '$path: the text is shorter than $minLength characters.';
      }
      final maxLength = schema['maxLength'];
      if (maxLength is int && value.length > maxLength) {
        return '$path: the text is longer than $maxLength characters.';
      }
    }
    if (value is List) {
      final minItems = schema['minItems'];
      if (minItems is int && value.length < minItems) {
        return '$path: at least $minItems items are expected.';
      }
      final maxItems = schema['maxItems'];
      if (maxItems is int && value.length > maxItems) {
        return '$path: at most $maxItems items are expected.';
      }
      final items = schema['items'];
      if (items is Map) {
        final itemSchema = items.cast<String, Object?>();
        for (var index = 0; index < value.length; index++) {
          final error = _check(value[index], itemSchema, '$path, item $index');
          if (error != null) return error;
        }
      }
    }
    if (value is Map) {
      final required = schema['required'];
      if (required is List) {
        for (final name in required) {
          if (name is String && !value.containsKey(name)) {
            return '$path: the required member "$name" is missing.';
          }
        }
      }
      final properties = schema['properties'];
      final propertySchemas = properties is Map
          ? properties.cast<Object?, Object?>()
          : const <Object?, Object?>{};
      final additional = schema['additionalProperties'];
      for (final entry in value.entries) {
        final name = entry.key is String ? entry.key as String : '${entry.key}';
        final propertySchema = propertySchemas[name];
        if (propertySchema is Map) {
          final label = path == 'the arguments'
              ? 'the member "$name"'
              : '$path, member "$name"';
          final error = _check(
            entry.value,
            propertySchema.cast<String, Object?>(),
            label,
          );
          if (error != null) return error;
        } else if (additional == false) {
          final known = propertySchemas.keys.whereType<String>().join(', ');
          return '$path: unknown member "$name"'
              '${known.isEmpty ? '.' : ' (known members: $known).'}';
        }
      }
    }
    return null;
  }

  /// The values accepted by a `type` keyword, as a list (`null` when absent).
  List<String>? _typesOf(Object? type) {
    if (type is String) return <String>[type];
    if (type is List) return type.whereType<String>().toList();
    return null;
  }

  bool _matchesType(Object? value, String type) {
    switch (type) {
      case 'object':
        return value is Map;
      case 'array':
        return value is List;
      case 'string':
        return value is String;
      case 'number':
        return value is num;
      case 'integer':
        if (value is int) return true;
        return value is double && value.isFinite && value == value.roundToDouble();
      case 'boolean':
        return value is bool;
      case 'null':
        return value == null;
      default:
        // An unknown type name must not reject a value.
        return true;
    }
  }

  bool _sameValue(Object? a, Object? b) {
    if (a == b) return true;
    if (a is Map || a is List || b is Map || b is List) {
      return jsonEncode(a) == jsonEncode(b);
    }
    return false;
  }

  String _join(List<String> values) {
    if (values.length == 1) return values.first;
    return '${values.sublist(0, values.length - 1).join(', ')} or ${values.last}';
  }

  String _describe(Object? value) {
    if (value == null) return 'no value';
    if (value is String) return 'a string';
    if (value is bool) return 'a boolean';
    if (value is int) return 'an integer';
    if (value is double) return 'a number';
    if (value is num) return 'a number';
    if (value is List) return 'a list';
    if (value is Map) return 'an object';
    return '${value.runtimeType}';
  }

  String _literal(Object? value) {
    if (value is String) return '"$value"';
    if (value is num || value is bool) return '$value';
    return jsonEncode(value);
  }
}
