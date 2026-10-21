import 'package:sdui_mutable_state_sync/store.dart';
import 'package:test/test.dart';

void main() {
  group('Nível 1 — transação local', () {
    test('chave ausente devolve null', () {
      final result = Store('n1').commit([
        ['r', 4, null],
      ]);

      expect(result.txn, [
        ['r', 4, null],
      ]);
      expect(result.written, isEmpty);
    });

    test('escrita é visível para a leitura seguinte da mesma transação', () {
      final result = Store('n1').commit([
        ['r', 1, null],
        ['w', 1, 42],
        ['r', 1, null],
        ['w', 2, 7],
        ['r', 2, null],
      ]);

      expect(result.txn, [
        ['r', 1, null],
        ['w', 1, 42],
        ['r', 1, 42],
        ['w', 2, 7],
        ['r', 2, 7],
      ]);
    });

    test('transação seguinte lê o que já foi commitado', () {
      final store = Store('n1');
      store.commit([
        ['w', 1, 42],
      ]);

      expect(
        store.commit([
          ['r', 1, null],
        ]).txn,
        [
          ['r', 1, 42],
        ],
      );
    });
  });

  group('Nível 2 — duplicata, atraso e leitura obsoleta', () {
    test('réplica que ainda não recebeu o gossip não vê a escrita', () {
      final local = Store('n1');
      final remote = Store('n2');
      local.commit([
        ['w', 1, 42],
      ]);

      expect(remote.valueOf(1), isNull);
    });

    test('aplicar o mesmo gossip duas vezes não muda o estado', () {
      final local = Store('n1');
      final remote = Store('n2');
      local.commit([
        ['w', 1, 42],
      ]);
      final snap = local.snapshot();

      remote.merge(snap.clock, snap.entries);
      final once = _dump(remote);
      remote.merge(snap.clock, snap.entries);

      expect(_dump(remote), once);
      expect(remote.valueOf(1), 42);
    });

    test('gossip antigo não apaga um valor mais novo', () {
      final local = Store('n1');
      final remote = Store('n2');
      local.commit([
        ['w', 1, 1],
      ]);
      final old = local.snapshot();
      local.commit([
        ['w', 1, 2],
      ]);

      remote.merge(local.snapshot().clock, local.snapshot().entries);
      remote.merge(old.clock, old.entries);

      expect(remote.valueOf(1), 2);
    });

    test('empate de timestamp fica com o node id maior', () {
      final a = Store('n1')
        ..commit([
          ['w', 1, 10],
        ]);
      final b = Store('n2')
        ..commit([
          ['w', 1, 20],
        ]);

      _exchange(a, b);

      expect(a.valueOf(1), 20);
      expect(a.writerOf(1), 'n2');
      expect(b.valueOf(1), 20);
      expect(b.writerOf(1), 'n2');
    });
  });

  group('Nível 3 — divergir durante a partição e convergir depois', () {
    test('cada nó commita sozinho e os mapas se encontram', () {
      final a = Store('n1')
        ..commit([
          ['w', 1, 10],
        ]);
      final b = Store('n2')
        ..commit([
          ['w', 2, 20],
        ]);

      _exchange(a, b);

      expect(_dump(a), _dump(b));
      expect(a.valueOf(1), 10);
      expect(a.valueOf(2), 20);
    });

    test('a escrita seguinte fica depois do relógio observado', () {
      final a = Store('n1');
      a.commit([
        ['w', 1, 1],
      ]);
      a.commit([
        ['w', 1, 2],
      ]);
      a.commit([
        ['w', 1, 3],
      ]);
      final b = Store('n2');
      b.merge(a.snapshot().clock, a.snapshot().entries);

      b.commit([
        ['w', 1, 9],
      ]);

      expect(b.timestampOf(1), 4);
      expect(b.valueOf(1), 9);
    });
  });

  group('Nível 4 — uma versão por transação', () {
    test('leitura não publica versão nova', () {
      final store = Store('n1')
        ..commit([
          ['w', 1, 5],
        ]);
      final clock = store.clock;

      final result = store.commit([
        ['r', 1, null],
      ]);

      expect(result.written, isEmpty);
      expect(store.clock, clock);
      expect(result.txn, [
        ['r', 1, 5],
      ]);
    });

    test('as duas chaves da transação compartilham timestamp e autor', () {
      final store = Store('n1')
        ..commit([
          ['w', 1, 5],
          ['w', 2, 6],
          ['w', 1, 7],
        ]);

      expect(store.valueOf(1), 7);
      expect(store.valueOf(2), 6);
      expect(store.timestampOf(1), store.timestampOf(2));
      expect(store.writerOf(1), store.writerOf(2));
      expect(store.snapshot().entries, hasLength(2));
    });

    test('a réplica observa só o valor final, não o intermediário', () {
      final local = Store('n1');
      final remote = Store('n2');
      final result = local.commit([
        ['w', 1, 1],
        ['w', 1, 2],
        ['r', 1, null],
      ]);

      expect(result.txn.last, ['r', 1, 2]);
      expect(result.written, hasLength(1));
      remote.merge(local.clock, result.written);

      expect(remote.valueOf(1), 2);
    });

    test('duas transações não fraturam as chaves que escreveram juntas', () {
      final a = Store('n1')
        ..commit([
          ['w', 1, 10],
          ['w', 2, 11],
        ]);
      final b = Store('n2')
        ..commit([
          ['w', 1, 20],
          ['w', 2, 21],
        ]);

      _exchange(a, b);

      expect(a.writerOf(1), a.writerOf(2));
      expect(a.writerOf(1), 'n2');
      expect(a.valueOf(1), 20);
      expect(a.valueOf(2), 21);
      expect(_dump(a), _dump(b));
    });
  });
}

void _exchange(Store a, Store b) {
  final snapA = a.snapshot();
  final snapB = b.snapshot();
  a.merge(snapB.clock, snapB.entries);
  b.merge(snapA.clock, snapA.entries);
}

String _dump(Store store) {
  final entries = [...store.snapshot().entries]
    ..sort((a, b) => a.key.compareTo(b.key));
  final body = entries
      .map(
        (entry) =>
            '${entry.key}:${entry.timestamp}:${entry.writer}:${entry.value}',
      )
      .join(',');
  return '${store.clock}|$body';
}
