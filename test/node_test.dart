import 'dart:convert';

import 'package:sdui_mutable_state_sync/node.dart';
import 'package:test/test.dart';

void main() {
  test('init, txn e replicate entre dois nós', () {
    final fromA = <Map<String, Object?>>[];
    final fromB = <Map<String, Object?>>[];
    final nodeA = Node(
      gossipInterval: const Duration(days: 1),
      emit: fromA.add,
    );
    final nodeB = Node(
      gossipInterval: const Duration(days: 1),
      emit: fromB.add,
    );
    addTearDown(nodeA.dispose);
    addTearDown(nodeB.dispose);

    nodeA.handleLine(
      _message('c0', 'n1', {
        'type': 'init',
        'node_id': 'n1',
        'node_ids': ['n1', 'n2'],
        'msg_id': 1,
      }),
    );
    nodeB.handleLine(
      _message('c0', 'n2', {
        'type': 'init',
        'node_id': 'n2',
        'node_ids': ['n1', 'n2'],
        'msg_id': 1,
      }),
    );

    expect(fromA.single['dest'], 'c0');
    expect(fromA.single['body'], {'type': 'init_ok', 'in_reply_to': 1});

    nodeA.handleLine(
      _message('c1', 'n1', {
        'type': 'txn',
        'msg_id': 2,
        'txn': [
          ['r', 1, null],
          ['w', 1, 42],
          ['r', 1, null],
        ],
      }),
    );

    expect(fromA[1]['dest'], 'c1');
    expect(fromA[1]['body'], {
      'type': 'txn_ok',
      'in_reply_to': 2,
      'txn': [
        ['r', 1, null],
        ['w', 1, 42],
        ['r', 1, 42],
      ],
    });
    expect(fromA[2]['dest'], 'n2');
    expect((fromA[2]['body'] as Map)['type'], 'replicate');

    nodeB.handleLine(jsonEncode(fromA[2]));
    nodeB.handleLine(
      _message('c2', 'n2', {
        'type': 'txn',
        'msg_id': 3,
        'txn': [
          ['r', 1, null],
        ],
      }),
    );

    expect(fromB.last['body'], {
      'type': 'txn_ok',
      'in_reply_to': 3,
      'txn': [
        ['r', 1, 42],
      ],
    });
  });
}

String _message(String src, String dest, Map<String, Object?> body) {
  return jsonEncode({'src': src, 'dest': dest, 'body': body});
}
