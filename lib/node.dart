import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'store.dart';

/// Nó Maelstrom: responde na hora e replica o que já commitou.
class Node {
  Node({
    required this.emit,
    this.gossipInterval = const Duration(milliseconds: 100),
  });

  final void Function(Map<String, Object?> message) emit;
  final Duration gossipInterval;

  String? _nodeId;
  List<String> _peers = const [];
  Store? _store;
  Timer? _gossipTimer;

  void dispose() {
    _gossipTimer?.cancel();
    _gossipTimer = null;
  }

  void handleLine(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      throw const FormatException('mensagem inválida');
    }
    final message = Map<String, dynamic>.from(decoded);
    final src = message['src'] as String;
    final bodyRaw = message['body'];
    if (bodyRaw is! Map) {
      throw const FormatException('corpo inválido');
    }
    final body = Map<String, dynamic>.from(bodyRaw);
    switch (body['type']) {
      case 'init':
        _onInit(src, body);
      case 'txn':
        _onTxn(src, body);
      case 'replicate':
        _onReplicate(body);
      default:
        stderr.writeln('mensagem ignorada: ${body['type']}');
    }
  }

  void _onInit(String src, Map<String, dynamic> body) {
    final nodeId = body['node_id'] as String;
    final nodeIds = [for (final id in body['node_ids'] as List) id as String];
    _nodeId = nodeId;
    _peers = [
      for (final id in nodeIds)
        if (id != nodeId) id,
    ];
    _store = Store(nodeId);
    _send(src, {'type': 'init_ok', 'in_reply_to': body['msg_id'] as int});
    stderr.writeln('nó $nodeId iniciado; pares: ${_peers.join(', ')}');
    _gossipTimer?.cancel();
    _gossipTimer = Timer.periodic(gossipInterval, (_) => _gossipFull());
  }

  void _onTxn(String src, Map<String, dynamic> body) {
    final store = _store;
    if (store == null) {
      throw StateError('txn antes do init');
    }
    final txn = [
      for (final op in body['txn'] as List)
        [for (final part in op as List) part as Object?],
    ];
    final result = store.commit(txn);
    _send(src, {
      'type': 'txn_ok',
      'in_reply_to': body['msg_id'] as int,
      'txn': result.txn,
    });
    if (result.written.isNotEmpty) {
      _gossip(result.written);
    }
  }

  void _onReplicate(Map<String, dynamic> body) {
    final store = _store;
    if (store == null) return;
    final rawEntries = body['entries'];
    if (rawEntries is! List) return;
    final entries = <VersionedEntry>[
      for (final raw in rawEntries)
        if (raw is Map)
          VersionedEntry(
            key: _asInt(raw['k']),
            timestamp: _asInt(raw['ts']),
            writer: raw['writer'] as String,
            value: _asInt(raw['v']),
          ),
    ];
    store.merge(_asInt(body['clock']), entries);
  }

  void _gossipFull() {
    final store = _store;
    if (store == null) return;
    _gossip(store.snapshot().entries);
  }

  void _gossip(List<VersionedEntry> entries) {
    final store = _store;
    final nodeId = _nodeId;
    if (store == null || nodeId == null || _peers.isEmpty) return;
    final body = <String, Object?>{
      'type': 'replicate',
      'clock': store.clock,
      'entries': [
        for (final entry in entries)
          {
            'k': entry.key,
            'ts': entry.timestamp,
            'writer': entry.writer,
            'v': entry.value,
          },
      ],
    };
    for (final peer in _peers) {
      _send(peer, body);
    }
  }

  void _send(String dest, Map<String, Object?> body) {
    final nodeId = _nodeId;
    if (nodeId == null) {
      throw StateError('envio antes do init');
    }
    emit({'src': nodeId, 'dest': dest, 'body': body});
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('inteiro esperado, recebi $value');
}

/// Lê o protocolo no stdin e escreve só JSON no stdout.
Future<void> runNode({
  Duration gossipInterval = const Duration(milliseconds: 100),
}) async {
  Future<void> flush = Future<void>.value();
  final node = Node(
    gossipInterval: gossipInterval,
    emit: (message) {
      stdout.writeln(jsonEncode(message));
      flush = flush.then((_) => stdout.flush());
    },
  );
  try {
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      try {
        node.handleLine(line);
      } catch (error, stackTrace) {
        stderr.writeln('erro ao processar mensagem: $error\n$stackTrace');
      }
    }
  } finally {
    node.dispose();
    await flush;
  }
}
