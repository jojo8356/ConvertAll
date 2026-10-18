// mcp_protocol.dart, the Model Context Protocol constants and message shapes.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// Reference: Model Context Protocol specification, revision 2026-07-28
// (https://modelcontextprotocol.io/specification/2026-07-28), plus the legacy
// revisions that used the `initialize` handshake.  The implementation notes
// are in `docs/MCP.md`.

/// The protocol revision implemented natively: the stateless "modern" era,
/// where every request carries its version, client identity and capabilities
/// in `_meta`, and `server/discover` replaces the old handshake.
const modernProtocolVersion = '2026-07-28';

/// The revisions of the "legacy" era, which open the conversation with an
/// `initialize` request.  They are still served, because most clients in the
/// wild speak them; see the compatibility matrix of the specification.
const legacyProtocolVersions = <String>[
  '2025-11-25',
  '2025-06-18',
  '2025-03-26',
  '2024-11-05',
];

/// The revision answered to a legacy client that asks for an unknown one,
/// as the legacy negotiation rules require the server to answer with a
/// revision it supports.
const latestLegacyProtocolVersion = '2025-11-25';

/// The JSON-RPC version of every message.
const jsonRpcVersion = '2.0';

/// True when [version] is the modern revision implemented here.
bool isModernProtocolVersion(String version) => version == modernProtocolVersion;

/// True when [version] is a legacy revision served through `initialize`.
bool isLegacyProtocolVersion(String version) => legacyProtocolVersions.contains(version);

/// The `_meta` keys reserved by the specification.
abstract final class MetaKeys {
  /// Protocol version of a request (modern era), required.
  static const protocolVersion = 'io.modelcontextprotocol/protocolVersion';

  /// Client name and version (modern era), optional but recommended.
  static const clientInfo = 'io.modelcontextprotocol/clientInfo';

  /// Client capabilities relevant to the request (modern era), required.
  static const clientCapabilities = 'io.modelcontextprotocol/clientCapabilities';

  /// Server name and version, in the `_meta` of every result (modern era).
  static const serverInfo = 'io.modelcontextprotocol/serverInfo';

  /// Minimum log level the server should emit for a request.
  ///
  /// Not used: this server never sends `notifications/message` (the logging
  /// feature is deprecated by the 2026-07-28 revision, which recommends
  /// writing to stderr instead).  The key is still listed so that a client
  /// sending it is understood and ignored.
  static const logLevel = 'io.modelcontextprotocol/logLevel';

  /// Opts a request into progress notifications.
  static const progressToken = 'progressToken';
}

/// The JSON-RPC and MCP error codes used by this server.
///
/// The specification partitions the JSON-RPC server error range: `-32000` to
/// `-32019` is implementation defined (not used here), `-32020` to `-32099` is
/// reserved for MCP itself.
abstract final class McpErrorCodes {
  /// Invalid JSON: the message could not be parsed.
  static const parseError = -32700;

  /// Not a valid JSON-RPC request object.
  static const invalidRequest = -32600;

  /// The method is not supported by this server.
  static const methodNotFound = -32601;

  /// The parameters are missing or do not match the schema (this is also the
  /// code for an unknown tool, and for a request of the modern era that does
  /// not carry its required `_meta` fields).
  static const invalidParams = -32602;

  /// An unexpected failure inside the server.
  static const internalError = -32603;

  /// A request header does not match the message body (Streamable HTTP only;
  /// kept for completeness).
  static const headerMismatch = -32020;

  /// The request needs a client capability that was not declared.
  static const missingRequiredClientCapability = -32021;

  /// The requested protocol version is not supported; `data.supported` lists
  /// the versions the server does implement.
  static const unsupportedProtocolVersion = -32022;
}

/// Name and version of a client or of a server, as carried by `_meta`.
class Implementation {
  const Implementation({
    required this.name,
    required this.version,
    this.title,
    this.description,
    this.websiteUrl,
  });

  final String name;
  final String version;
  final String? title;
  final String? description;
  final String? websiteUrl;

  Map<String, Object?> toJson() => {
    'name': name,
    'version': version,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (websiteUrl != null) 'websiteUrl': websiteUrl,
  };
}

/// A JSON-RPC error, thrown by the request handlers and turned into a
/// JSON-RPC error response by the server.
class JsonRpcException implements Exception {
  JsonRpcException(this.code, this.message, {this.data});

  /// One of the [McpErrorCodes] values.
  final int code;

  /// Human readable message, shown to the user by the client.
  final String message;

  /// Optional structured detail, e.g. `{"supported": [...]}`.
  final Map<String, Object?>? data;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    if (data != null) 'data': data,
  };

  /// The error response for [id].
  Map<String, Object?> toResponse(Object? id) => {
    'jsonrpc': jsonRpcVersion,
    'id': id,
    'error': toJson(),
  };

  @override
  String toString() => 'JsonRpcException($code): $message';
}
