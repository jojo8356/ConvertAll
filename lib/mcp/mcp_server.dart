// mcp_server.dart, the ConvertAll Model Context Protocol server.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// A "dual era" server, as described by the compatibility matrix of the
// specification:
//
//  * a request that carries the modern per-request metadata
//    (`_meta["io.modelcontextprotocol/protocolVersion"]`) is served
//    statelessly, following revision 2026-07-28: `server/discover` is
//    implemented, every result carries `resultType`, the cacheable results
//    carry `ttlMs` and `cacheScope`, and no handshake is needed;
//  * an `initialize` request selects the legacy era for the rest of the
//    process, exactly like the revisions up to 2025-11-25 are specified;
//  * a request that carries neither is rejected with an explanation, since
//    the modern revision requires the metadata on every request.
//
// There is no state other than the era of the process, and no server to
// client request: `notifications/message` is never sent (the specification
// recommends writing to stderr on the stdio transport, and the logging
// feature is deprecated), and no `subscriptions/listen` stream is offered.

import 'dart:convert' show json;

import '../core/app_info.dart';
import '../core/conversion_engine.dart';
import '../core/unit_exceptions.dart';
import 'json_schema.dart';
import 'mcp_protocol.dart';
import 'mcp_tools.dart';

/// The MCP server of ConvertAll.
class McpServer {
  McpServer({
    required ConversionEngine engine,
    this.serverName = 'convertall',
    this.serverVersion = '1.0.0',
    this.logger,
  }) : engine = engine,
       serverInfo = Implementation(
         name: serverName,
         version: serverVersion,
         title: 'ConvertAll unit conversion',
         description:
             'Unit conversion server backed by the unit database of the '
             'ConvertAll application.',
         websiteUrl: convertAllWebsite,
       ) {
    tools = buildConversionTools(engine);
    instructions = conversionInstructions(engine);
  }

  /// The conversion engine used by the tools.
  final ConversionEngine engine;

  /// Name reported as the server name.
  final String serverName;

  /// Version reported as the server version.
  final String serverVersion;

  /// Called with a line for every protocol exchange, when set.  The stdio
  /// entry point points it at stderr, never at stdout.
  final void Function(String message)? logger;

  /// The implementation description sent in `_meta` and in `initialize`.
  final Implementation serverInfo;

  /// The tools of the server, in a deterministic order (the specification
  /// recommends a stable order so that clients can cache the list).
  late final List<McpTool> tools;

  /// The guidance sent in `instructions`.
  late final String instructions;

  /// The legacy revision negotiated by `initialize`, or `null` while the
  /// process has not seen an `initialize` request.
  String? _legacyRevision;

  /// True once an `initialize` request selected the legacy era.
  bool get isLegacyEra => _legacyRevision != null;

  /// The legacy revision in use, or `null`.
  String? get legacyRevision => _legacyRevision;

  /// How long a client may cache the tool list and the discovery result.
  static const cacheTtlMs = 3600000;

  /// The methods this server answers.
  static const supportedMethods = <String>[
    'initialize',
    'server/discover',
    'tools/list',
    'tools/call',
    'ping',
  ];

  /// Handle one line of the stdio transport and return the JSON texts to
  /// write back (empty for a notification, one for a request).
  List<String> handleLine(String line) {
    Object? decoded;
    try {
      decoded = json.decode(line);
    } on FormatException {
      return [
        json.encode(
          JsonRpcException(
            McpErrorCodes.parseError,
            'Parse error: the message is not valid JSON.',
          ).toResponse(null),
        ),
      ];
    }
    if (decoded is! Map) {
      return [
        json.encode(
          JsonRpcException(
            McpErrorCodes.invalidRequest,
            'Invalid request: a JSON-RPC message must be a JSON object.',
          ).toResponse(null),
        ),
      ];
    }
    final response = handleMessage(decoded.cast<String, Object?>());
    if (response == null) return const [];
    return [json.encode(response)];
  }

  /// Handle one decoded JSON-RPC message.
  ///
  /// Return the message to send back, or `null` when nothing must be sent
  /// (a notification, or a request the specification forbids answering).
  Map<String, Object?>? handleMessage(Map<String, Object?> message) {
    final hasId = message.containsKey('id') && message['id'] != null;
    final id = message['id'];
    final method = message['method'];
    final rawParams = message['params'];
    final params = rawParams is Map
        ? rawParams.cast<String, Object?>()
        : const <String, Object?>{};
    if (message['jsonrpc'] != jsonRpcVersion || method is! String) {
      _log('rejected a malformed message');
      if (!hasId) return null;
      return JsonRpcException(
        McpErrorCodes.invalidRequest,
        'Invalid JSON-RPC request: "jsonrpc" must be "$jsonRpcVersion" and '
        '"method" must be a string.',
      ).toResponse(id);
    }
    if (!hasId) {
      _handleNotification(method, params);
      return null;
    }
    try {
      _log('<- $method${isLegacyEra ? ' (legacy ${_legacyRevision!})' : ''}');
      final result = _handleRequest(method, params);
      if (result == null) return null;
      return {'jsonrpc': jsonRpcVersion, 'id': id, 'result': result};
    } on JsonRpcException catch (error) {
      _log('-> error for $method: ${error.message}');
      return error.toResponse(id);
    } on UnitConversionException catch (error) {
      // The tools catch this themselves; reaching here means a bug, not a
      // user error, so it is reported as a server error.
      _log('-> unexpected conversion error for $method: $error');
      return JsonRpcException(
        McpErrorCodes.internalError,
        'Internal error while handling "$method".',
      ).toResponse(id);
    } catch (error) {
      _log('-> unexpected error for $method: $error');
      return JsonRpcException(
        McpErrorCodes.internalError,
        'Internal error while handling "$method".',
      ).toResponse(id);
    }
  }

  Map<String, Object?>? _handleRequest(
    String method,
    Map<String, Object?> params,
  ) {
    switch (method) {
      case 'initialize':
        return _initializeResult(params);
      case 'server/discover':
        _requireModernRequest(params, method);
        return _discoverResult();
      case 'tools/list':
        _requireModernRequest(params, method);
        return _listToolsResult();
      case 'tools/call':
        _requireModernRequest(params, method);
        return _callToolResult(params);
      case 'ping':
        // Removed by the 2026-07-28 revision; still answered for a client of
        // the legacy era.
        if (isLegacyEra) return const <String, Object?>{};
        throw JsonRpcException(
          McpErrorCodes.methodNotFound,
          'Method not found: "ping" was removed by protocol revision '
          '$modernProtocolVersion.',
          data: {'supportedMethods': supportedMethods},
        );
      default:
        throw JsonRpcException(
          McpErrorCodes.methodNotFound,
          'Method not found: $method',
          data: {
            'supportedMethods': supportedMethods,
            'protocolVersions': const [modernProtocolVersion],
          },
        );
    }
  }

  void _handleNotification(String method, Map<String, Object?> params) {
    switch (method) {
      case 'notifications/initialized':
        // The legacy handshake is complete; the server keeps serving the
        // legacy era until the process ends.
        _log('legacy handshake complete');
        break;
      case 'notifications/cancelled':
        _log('a request was cancelled');
        break;
      default:
        _log('ignored notification $method');
    }
  }

  /// Check the per-request metadata required by the modern revision, unless
  /// the process is already serving the legacy era.
  void _requireModernRequest(Map<String, Object?> params, String method) {
    if (isLegacyEra) return;
    final rawMeta = params['_meta'];
    final meta = rawMeta is Map ? rawMeta.cast<String, Object?>() : null;
    if (meta == null) {
      throw JsonRpcException(
        McpErrorCodes.invalidParams,
        'A "$method" request of protocol revision $modernProtocolVersion must '
        'carry the protocol version and the client capabilities in its '
        '"params._meta" ("${MetaKeys.protocolVersion}" and '
        '"${MetaKeys.clientCapabilities}").  A client of an earlier revision '
        'opens the conversation with an "initialize" request instead.',
        data: {'supportedVersions': const [modernProtocolVersion]},
      );
    }
    final version = meta[MetaKeys.protocolVersion];
    if (version is! String) {
      throw JsonRpcException(
        McpErrorCodes.invalidParams,
        'The "_meta" member "${MetaKeys.protocolVersion}" is required on '
        'every request of protocol revision $modernProtocolVersion.',
        data: {'supportedVersions': const [modernProtocolVersion]},
      );
    }
    if (!isModernProtocolVersion(version)) {
      throw JsonRpcException(
        McpErrorCodes.unsupportedProtocolVersion,
        'Unsupported protocol version',
        data: {
          'supported': const [modernProtocolVersion],
          'requested': version,
        },
      );
    }
    if (!meta.containsKey(MetaKeys.clientCapabilities)) {
      throw JsonRpcException(
        McpErrorCodes.invalidParams,
        'The "_meta" member "${MetaKeys.clientCapabilities}" is required on '
        'every request of protocol revision $modernProtocolVersion.',
        data: {'supportedVersions': const [modernProtocolVersion]},
      );
    }
  }

  /// The `initialize` result: this selects the legacy era for the rest of the
  /// process and negotiates the revision, as the revisions up to 2025-11-25
  /// specify.
  Map<String, Object?> _initializeResult(Map<String, Object?> params) {
    final requested = params['protocolVersion'];
    final negotiated = requested is String && isLegacyProtocolVersion(requested)
        ? requested
        : latestLegacyProtocolVersion;
    _legacyRevision = negotiated;
    _log('legacy era selected, revision $negotiated');
    return {
      'protocolVersion': negotiated,
      'capabilities': _serverCapabilities(),
      'serverInfo': serverInfo.toJson(),
      'instructions': instructions,
    };
  }

  /// The `server/discover` result, always in the modern shape: the method
  /// itself only exists in the modern revision.
  Map<String, Object?> _discoverResult() => {
    'resultType': 'complete',
    'supportedVersions': const [modernProtocolVersion],
    'capabilities': _serverCapabilities(),
    'instructions': instructions,
    'ttlMs': cacheTtlMs,
    'cacheScope': 'public',
    '_meta': {MetaKeys.serverInfo: serverInfo.toJson()},
  };

  Map<String, Object?> _listToolsResult() {
    final toolList = tools.map((tool) => tool.toJson()).toList();
    if (isLegacyEra) return {'tools': toolList};
    return {
      'resultType': 'complete',
      'tools': toolList,
      // The list never changes and is the same for every client.
      'ttlMs': cacheTtlMs,
      'cacheScope': 'public',
      '_meta': {MetaKeys.serverInfo: serverInfo.toJson()},
    };
  }

  Map<String, Object?> _callToolResult(Map<String, Object?> params) {
    final name = params['name'];
    if (name is! String) {
      throw JsonRpcException(
        McpErrorCodes.invalidParams,
        'A "tools/call" request must name the tool in its "name" member.',
      );
    }
    McpTool? tool;
    for (final candidate in tools) {
      if (candidate.name == name) {
        tool = candidate;
        break;
      }
    }
    if (tool == null) {
      // Unknown tool: a protocol error, since the model cannot fix a name
      // that does not exist (the available names are listed in `data`).
      throw JsonRpcException(
        McpErrorCodes.invalidParams,
        'Unknown tool: $name',
        data: {'availableTools': tools.map((candidate) => candidate.name).toList()},
      );
    }
    final rawArguments = params['arguments'];
    final arguments = rawArguments is Map
        ? rawArguments.cast<String, Object?>()
        : <String, Object?>{};
    final validator = JsonSchemaValidator(tool.inputSchema);
    final validationError = validator.validate(arguments);
    if (validationError != null) {
      throw JsonRpcException(
        McpErrorCodes.invalidParams,
        'Invalid arguments for tool "$name": $validationError',
        data: {'tool': name, 'inputSchema': tool.inputSchema},
      );
    }
    final outcome = tool.handler(validator.withDefaults(arguments));
    _log('   $name -> ${outcome.isError ? 'error ${outcome.errorCode}' : 'ok'}');
    return _toolResult(outcome);
  }

  /// Turn a tool outcome into a `CallToolResult`.
  ///
  /// A failure of the tool itself is reported in the result with
  /// `isError: true`, as the specification requires, so that the model reads
  /// the explanation; only an unknown tool or invalid arguments produce a
  /// JSON-RPC error.
  Map<String, Object?> _toolResult(ToolOutcome outcome) {
    final content = <Map<String, Object?>>[
      {'type': 'text', 'text': outcome.text},
    ];
    if (outcome.isError) {
      content.add({
        'type': 'text',
        'text': json.encode({
          'error_code': outcome.errorCode,
          'message': outcome.text,
          if (outcome.suggestions.isNotEmpty) 'suggestions': outcome.suggestions,
        }),
      });
    } else if (outcome.structured != null) {
      // The specification asks a tool that returns structured content to also
      // return the serialised JSON in a text block, for older clients.
      content.add({'type': 'text', 'text': json.encode(outcome.structured)});
    }
    final result = <String, Object?>{'content': content};
    if (!outcome.isError && outcome.structured != null) {
      result['structuredContent'] = outcome.structured;
    }
    if (outcome.isError) result['isError'] = true;
    if (!isLegacyEra) {
      result['resultType'] = 'complete';
      result['_meta'] = {MetaKeys.serverInfo: serverInfo.toJson()};
    }
    return result;
  }

  Map<String, Object?> _serverCapabilities() => {
    'tools': {'listChanged': false},
  };

  void _log(String message) => logger?.call(message);
}
