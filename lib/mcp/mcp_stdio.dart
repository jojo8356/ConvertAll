// mcp_stdio.dart, the stdio transport of the MCP server.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The stdio transport of the specification: one JSON-RPC message per line on
// stdin, one per line on stdout, and nothing else on stdout — every trace,
// warning and error goes to stderr.  The server exits when its input stream is
// closed, which the specification calls "the primary graceful-shutdown signal".

import 'dart:convert' show LineSplitter, utf8;
import 'dart:io' show IOSink, ProcessSignal, exit, stderr, stdin, stdout;

import 'mcp_server.dart';

/// Serve [server] on the stdio transport until the input stream ends.
///
/// [input], [output] and [logOutput] default to the process standard streams;
/// they are injectable so that a test can drive the server with plain strings.
Future<int> runStdioMcpServer(
  McpServer server, {
  Stream<List<int>>? input,
  IOSink? output,
  bool verbose = false,
}) async {
  final source = input ?? stdin;
  final sink = output ?? stdout;
  final lines = source.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final responses = server.handleLine(line);
    if (responses.isEmpty) continue;
    for (final response in responses) {
      // One message per line, with no embedded newline: `json.encode` never
      // emits a raw line break.
      sink.write(response);
      sink.write('\n');
    }
    await sink.flush();
  }
  if (verbose) stderr.writeln('[convertall-mcp] input closed, exiting');
  await sink.flush();
  return 0;
}

/// Exit cleanly when the client terminates the process with a signal.
///
/// A client normally shuts the server down by closing its stdin, which
/// [runStdioMcpServer] already handles; this covers the abrupt case.
void installTerminationHandlers({bool verbose = false}) {
  void handle(ProcessSignal signal) {
    if (verbose) stderr.writeln('[convertall-mcp] $signal received, exiting');
    // The transport flushes after every response, so there is nothing
    // pending; 0 because the client asked for the shutdown.
    exit(0);
  }

  // `sigterm` and `sigint` cannot be watched on every platform (Windows
  // throws), hence the two try/catch blocks.
  try {
    ProcessSignal.sigterm.watch().listen(handle);
  } catch (_) {
    // Not available here: the client closes stdin instead.
  }
  try {
    ProcessSignal.sigint.watch().listen(handle);
  } catch (_) {
    // Not available here.
  }
}
