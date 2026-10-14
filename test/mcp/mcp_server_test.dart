// mcp_server_test.dart, tests of the Model Context Protocol server.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// Run with:  flutter test test/mcp/mcp_server_test.dart
//
// Every test drives the server the way the stdio transport does — one JSON-RPC
// message — and checks the message that comes back.  The two eras of the
// protocol are covered: the stateless revision 2026-07-28 (per request `_meta`,
// `server/discover`, `resultType`, caching hints) and the legacy revisions that
// open with the `initialize` handshake.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:convertall/core/conversion_engine.dart';
import 'package:convertall/core/unit_database.dart';
import 'package:convertall/core/unit_exceptions.dart';
import 'package:convertall/mcp/mcp_protocol.dart';
import 'package:convertall/mcp/mcp_server.dart';

/// A server over the real unit data.
McpServer buildServer() {
  final unitsJson = File('assets/units.json').readAsStringSync();
  return McpServer(
    engine: ConversionEngine(UnitDatabase.fromJsonTexts(unitsJson)),
  );
}

/// A request of the modern era: the version and the client capabilities travel
/// in `_meta`, as the 2026-07-28 revision requires.
String modernRequest(
  Object id,
  String method, {
  Map<String, Object?>? params,
}) {
  // Every request of the modern era carries its metadata; a request without
  // arguments still has `params`, since `_meta` lives inside it.
  return json.encode({
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': {
      ...?params,
      '_meta': {
        MetaKeys.protocolVersion: modernProtocolVersion,
        MetaKeys.clientCapabilities: <String, Object?>{},
        MetaKeys.clientInfo: {'name': 'test-client', 'version': '1.0.0'},
      },
    },
  });
}

/// A request of the legacy era, without any `_meta`.
String legacyRequest(Object id, String method, {Map<String, Object?>? params}) {
  return json.encode({
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    if (params != null) 'params': params,
  });
}

/// Send one line and decode the single response.
Map<String, Object?> exchange(McpServer server, String line) {
  final responses = server.handleLine(line);
  expect(responses, hasLength(1), reason: 'one response expected for $line');
  return json.decode(responses.single) as Map<String, Object?>;
}

/// The `result` of a response, with a readable failure message.
Map<String, Object?> resultOf(Map<String, Object?> response) {
  expect(response['error'], isNull, reason: 'unexpected error: ${response['error']}');
  final result = response['result'];
  expect(result, isA<Map<String, Object?>>());
  return (result as Map).cast<String, Object?>();
}

/// The `error` of a response.
Map<String, Object?> errorOf(Map<String, Object?> response) {
  final error = response['error'];
  expect(error, isA<Map<String, Object?>>(), reason: 'an error was expected');
  return (error as Map).cast<String, Object?>();
}

/// Call a tool and return its result.
Map<String, Object?> callTool(
  McpServer server,
  String name,
  Map<String, Object?> arguments, {
  Object id = 1,
}) {
  return resultOf(
    exchange(
      server,
      modernRequest(
        id,
        'tools/call',
        params: {'name': name, 'arguments': arguments},
      ),
    ),
  );
}

void main() {
  group('modern era (revision $modernProtocolVersion)', () {
    late McpServer server;

    setUp(() {
      server = buildServer();
    });

    test('server/discover advertises versions, tools and caching', () {
      final result = resultOf(exchange(server, modernRequest(1, 'server/discover')));
      expect(result['resultType'], 'complete');
      expect(result['supportedVersions'], contains(modernProtocolVersion));
      final capabilities = (result['capabilities'] as Map).cast<String, Object?>();
      expect(capabilities['tools'], isNotNull);
      expect(result['ttlMs'], isA<int>());
      expect(result['cacheScope'], 'public');
      expect(result['instructions'], isA<String>());
      final meta = (result['_meta'] as Map).cast<String, Object?>();
      final info = (meta[MetaKeys.serverInfo] as Map).cast<String, Object?>();
      expect(info['name'], 'convertall');
      expect(info['version'], isA<String>());
    });

    test('tools/list returns the five tools with their schemas', () {
      final result = resultOf(exchange(server, modernRequest(1, 'tools/list')));
      expect(result['resultType'], 'complete');
      expect(result['ttlMs'], McpServer.cacheTtlMs);
      expect(result['cacheScope'], 'public');
      final tools = (result['tools'] as List).cast<Map<String, Object?>>();
      expect(tools.map((tool) => tool['name']).toList(), [
        'convert_value',
        'list_unit_types',
        'search_units',
        'get_unit_info',
        'find_compatible_units',
      ]);
      for (final tool in tools) {
        final name = tool['name'];
        final schema = (tool['inputSchema'] as Map).cast<String, Object?>();
        expect(schema['type'], 'object', reason: '$name');
        expect(tool['outputSchema'], isA<Map>(), reason: '$name');
        expect(tool['description'], isA<String>(), reason: '$name');
        expect((tool['description']! as String).length, greaterThan(80));
        final annotations = (tool['annotations'] as Map).cast<String, Object?>();
        expect(annotations['readOnlyHint'], isTrue, reason: '$name');
        expect(annotations['openWorldHint'], isFalse, reason: '$name');
      }
    });

    test('convert_value returns structured content and text blocks', () {
      final result = callTool(server, 'convert_value', {
        'value': '100',
        'from': 'km/hr',
        'to': 'm/s',
      });
      expect(result['resultType'], 'complete');
      expect(result['isError'], isNull);
      final structured = (result['structuredContent'] as Map)
          .cast<String, Object?>();
      expect(structured['result'], '27.77777778');
      expect(structured['value'], closeTo(27.77777777777778, 1e-9));
      expect(structured['from'], 'km/hr');
      expect(structured['to'], 'm/s');
      final content = (result['content'] as List).cast<Map<String, Object?>>();
      expect(content, hasLength(2));
      expect(content.first['type'], 'text');
      expect(content.first['text'], contains('27.77777778'));
      // The specification asks for the serialised JSON in a text block too.
      expect(json.decode(content.last['text']! as String), isA<Map>());
      final meta = (result['_meta'] as Map).cast<String, Object?>();
      expect(meta[MetaKeys.serverInfo], isNotNull);
    });

    test('convert_value accepts a number and a calculation', () {
      final fromNumber = callTool(server, 'convert_value', {
        'value': 1.5,
        'from': 'km',
        'to': 'm',
      });
      expect(
        ((fromNumber['structuredContent'] as Map)['value'] as num).toDouble(),
        1500.0,
      );
      final fromFraction = callTool(server, 'convert_value', {
        'value': '1/8',
        'from': 'cup',
        'to': 'ml',
      });
      expect(
        ((fromFraction['structuredContent'] as Map)['value'] as num).toDouble(),
        closeTo(29.5735295625, 1e-9),
      );
    });

    test('convert_value returns the details on demand', () {
      final result = callTool(server, 'convert_value', {
        'value': '1',
        'from': 'Btu',
        'to': 'J',
        'include_details': true,
      });
      final structured = (result['structuredContent'] as Map)
          .cast<String, Object?>();
      expect(structured['from_reduced'], 'kg * m^2 / s^2');
      expect(structured['to_reduced'], 'kg * m^2 / s^2');
      expect((structured['factor']! as num).toDouble(), closeTo(1055.05585262, 1e-6));
      expect(structured['from_category'], 'energy');
      expect(structured['notation'], 'short');
      expect(structured['decimals'], 8);
    });

    test('a failed conversion is reported inside the result', () {
      final result = callTool(server, 'convert_value', {
        'value': '1',
        'from': 'kg',
        'to': 'm',
      });
      expect(result['isError'], isTrue);
      expect(result.containsKey('structuredContent'), isFalse);
      final content = (result['content'] as List).cast<Map<String, Object?>>();
      expect(content.first['text'], contains('do not measure the same quantity'));
      final envelope = json.decode(content.last['text']! as String)
          as Map<String, Object?>;
      expect(envelope['error_code'], UnitErrorCode.incompatibleUnits);
    });

    test('an unknown unit produces suggestions for the model', () {
      final result = callTool(server, 'convert_value', {
        'value': '1',
        'from': 'metr',
        'to': 'm',
      });
      expect(result['isError'], isTrue);
      final content = (result['content'] as List).cast<Map<String, Object?>>();
      final envelope = json.decode(content.last['text']! as String)
          as Map<String, Object?>;
      expect(envelope['error_code'], UnitErrorCode.unknownUnit);
      expect(envelope['suggestions'], contains('metre'));
    });

    test('list_unit_types lists the quantities with their counts', () {
      final result = callTool(server, 'list_unit_types', {});
      final structured = (result['structuredContent'] as Map)
          .cast<String, Object?>();
      final types = (structured['types'] as List).cast<Map<String, Object?>>();
      expect(types, hasLength(52));
      final length = types.firstWhere((type) => type['type'] == 'length');
      expect(length['count'], isA<int>());
      expect(length['type_display'], isA<String>());
      expect(result['isError'], isNull);
    });

    test('search_units searches by name and filters by type', () {
      final byName = callTool(server, 'search_units', {'query': 'cel'});
      final units = ((byName['structuredContent'] as Map)['units'] as List)
          .cast<Map<String, Object?>>();
      expect(units.map((unit) => unit['name']), contains('Celsius'));
      // The optional members of the shape are omitted, never null.
      for (final unit in units) {
        expect(unit.containsKey('unabbrev'), isFalse);
      }
      final byType = callTool(server, 'search_units', {
        'type': 'volume',
        'limit': 5,
      });
      final volume = (byType['structuredContent'] as Map).cast<String, Object?>();
      final limited = volume['units'] as List;
      expect(limited, hasLength(5));
      expect((volume['count'] as num).toInt(), greaterThan(5));

      final noMatch = callTool(server, 'search_units', {'query': 'zzzz'});
      expect(noMatch['isError'], isNull);
      expect(((noMatch['structuredContent'] as Map)['count'] as num).toInt(), 0);
      final content = (noMatch['content'] as List).cast<Map<String, Object?>>();
      expect(content.first['text'], contains('No unit matches'));
    });

    test('get_unit_info describes a non-linear unit', () {
      final result = callTool(server, 'get_unit_info', {
        'unit': 'C',
        'compatible_limit': 3,
      });
      final structured = (result['structuredContent'] as Map)
          .cast<String, Object?>();
      expect(structured['unit'], 'C');
      expect(structured['type'], 'temperature');
      expect(structured['non_linear'], isTrue);
      expect(structured['base_units'], 'K');
      expect(structured['from_equation'], 'x + 273.15');
      expect(structured['compatible_unit_count'], isA<int>());
      expect(structured['compatible_units'], hasLength(3));
      expect(result['isError'], isNull);
    });

    test('find_compatible_units lists the units of the same quantity', () {
      final result = callTool(server, 'find_compatible_units', {
        'unit': 'km/hr',
        'limit': 100,
      });
      final structured = (result['structuredContent'] as Map)
          .cast<String, Object?>();
      // A compound expression reports the base units it reduces to.
      expect(structured['category'], 'm / s');
      final names = (structured['units'] as List)
          .cast<Map<String, Object?>>()
          .map((unit) => unit['name'])
          .toList();
      expect(names, contains('mph'));
      expect(names, contains('knot'));
      expect(names, isNot(contains('kg')));
    });

    test('an unknown tool is a protocol error with the available names', () {
      final response = exchange(
        server,
        modernRequest(9, 'tools/call', params: {'name': 'not_a_tool'}),
      );
      final error = errorOf(response);
      expect(error['code'], McpErrorCodes.invalidParams);
      expect(error['message'], contains('not_a_tool'));
      final data = (error['data'] as Map).cast<String, Object?>();
      expect(data['availableTools'], contains('convert_value'));
    });

    test('invalid arguments are a protocol error naming the member', () {
      final response = exchange(
        server,
        modernRequest(
          10,
          'tools/call',
          params: {
            'name': 'search_units',
            'arguments': {'limit': 1000},
          },
        ),
      );
      final error = errorOf(response);
      expect(error['code'], McpErrorCodes.invalidParams);
      expect(error['message'], contains('limit'));
      expect(error['message'], contains('maximum of 200'));
    });

    test('a missing argument is named in the error', () {
      final response = exchange(
        server,
        modernRequest(
          11,
          'tools/call',
          params: {
            'name': 'convert_value',
            'arguments': {'value': '1', 'from': 'km'},
          },
        ),
      );
      final error = errorOf(response);
      expect(error['code'], McpErrorCodes.invalidParams);
      expect(error['message'], contains('"to"'));
    });

    test('the per-request metadata is required', () {
      final response = exchange(server, legacyRequest(12, 'tools/list'));
      final error = errorOf(response);
      expect(error['code'], McpErrorCodes.invalidParams);
      expect(error['message'], contains('_meta'));
      expect(error['message'], contains('initialize'));
    });

    test('an unsupported version is refused with the supported list', () {
      final response = exchange(
        server,
        json.encode({
          'jsonrpc': '2.0',
          'id': 13,
          'method': 'tools/list',
          'params': {
            '_meta': {
              MetaKeys.protocolVersion: '1900-01-01',
              MetaKeys.clientCapabilities: <String, Object?>{},
            },
          },
        }),
      );
      final error = errorOf(response);
      expect(error['code'], McpErrorCodes.unsupportedProtocolVersion);
      final data = (error['data'] as Map).cast<String, Object?>();
      expect(data['supported'], [modernProtocolVersion]);
      expect(data['requested'], '1900-01-01');
    });

    test('ping was removed and is not found', () {
      final response = exchange(server, modernRequest(14, 'ping'));
      expect(errorOf(response)['code'], McpErrorCodes.methodNotFound);
    });

    test('an unknown method lists the supported ones', () {
      final response = exchange(server, modernRequest(15, 'resources/list'));
      final error = errorOf(response);
      expect(error['code'], McpErrorCodes.methodNotFound);
      final data = (error['data'] as Map).cast<String, Object?>();
      expect(data['supportedMethods'], contains('tools/call'));
    });

    test('a malformed line is a parse error, without an id', () {
      final responses = server.handleLine('this is not json');
      expect(responses, hasLength(1));
      final response = json.decode(responses.single) as Map<String, Object?>;
      expect((response['error'] as Map)['code'], McpErrorCodes.parseError);
      expect(response['id'], isNull);
    });

    test('a non-object message is an invalid request', () {
      final response = json.decode(server.handleLine('[1, 2]').single)
          as Map<String, Object?>;
      expect(errorOf(response)['code'], McpErrorCodes.invalidRequest);
    });

    test('a notification gets no answer', () {
      expect(
        server.handleLine(
          json.encode({'jsonrpc': '2.0', 'method': 'notifications/cancelled'}),
        ),
        isEmpty,
      );
    });
  });

  group('legacy era (initialize handshake)', () {
    late McpServer server;

    setUp(() {
      server = buildServer();
    });

    test('initialize negotiates the revision and selects the legacy era', () {
      final result = resultOf(
        exchange(
          server,
          legacyRequest(
            1,
            'initialize',
            params: {
              'protocolVersion': '2025-06-18',
              'capabilities': <String, Object?>{},
              'clientInfo': {'name': 'legacy-client', 'version': '1.0.0'},
            },
          ),
        ),
      );
      expect(result['protocolVersion'], '2025-06-18');
      expect((result['capabilities'] as Map)['tools'], isNotNull);
      final info = (result['serverInfo'] as Map).cast<String, Object?>();
      expect(info['name'], 'convertall');
      expect(server.isLegacyEra, isTrue);
      expect(server.legacyRevision, '2025-06-18');
    });

    test('answers the latest legacy revision when an unknown one is asked', () {
      final result = resultOf(
        exchange(
          server,
          legacyRequest(
            1,
            'initialize',
            params: {'protocolVersion': '1999-01-01'},
          ),
        ),
      );
      expect(result['protocolVersion'], latestLegacyProtocolVersion);
    });

    test('the handshake notification is accepted silently', () {
      exchange(
        server,
        legacyRequest(
          1,
          'initialize',
          params: {'protocolVersion': latestLegacyProtocolVersion},
        ),
      );
      expect(
        server.handleLine(
          json.encode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
        ),
        isEmpty,
      );
    });

    test('a legacy client is served without metadata and without resultType', () {
      exchange(
        server,
        legacyRequest(
          1,
          'initialize',
          params: {'protocolVersion': latestLegacyProtocolVersion},
        ),
      );
      final listResult = resultOf(exchange(server, legacyRequest(2, 'tools/list')));
      expect(listResult.containsKey('resultType'), isFalse);
      expect(listResult.containsKey('ttlMs'), isFalse);
      final tools = listResult['tools'] as List;
      expect(tools, hasLength(5));

      final callResult = resultOf(
        exchange(
          server,
          legacyRequest(
            3,
            'tools/call',
            params: {
              'name': 'convert_value',
              'arguments': {'value': '1', 'from': 'mile', 'to': 'km'},
            },
          ),
        ),
      );
      expect(callResult.containsKey('resultType'), isFalse);
      final structured = (callResult['structuredContent'] as Map)
          .cast<String, Object?>();
      expect(structured['result'], '1.609344');

      // `ping` still exists in the legacy revisions.
      final pingResult = resultOf(exchange(server, legacyRequest(4, 'ping')));
      expect(pingResult, isEmpty);
    });

    test('a legacy failure is still reported inside the result', () {
      exchange(
        server,
        legacyRequest(
          1,
          'initialize',
          params: {'protocolVersion': latestLegacyProtocolVersion},
        ),
      );
      final callResult = resultOf(
        exchange(
          server,
          legacyRequest(
            2,
            'tools/call',
            params: {
              'name': 'convert_value',
              'arguments': {'value': '1', 'from': 'kg', 'to': 'm'},
            },
          ),
        ),
      );
      expect(callResult['isError'], isTrue);
    });
  });
}
