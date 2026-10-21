/// Registro versionado de um nó.
///
/// Cada chave guarda a versão vencedora `(timestamp, writer, value)`.
/// Uma transação recebe um único timestamp, aplicado só aos valores finais.
class VersionedEntry {
  const VersionedEntry({
    required this.key,
    required this.timestamp,
    required this.writer,
    required this.value,
  });

  final int key;
  final int timestamp;
  final String writer;
  final int value;

  /// Ordem total: timestamp maior vence; empate fica com o `writer` maior.
  bool winsOver(VersionedEntry other) {
    if (timestamp != other.timestamp) return timestamp > other.timestamp;
    return writer.compareTo(other.writer) > 0;
  }

  @override
  String toString() => 'VersionedEntry($key @$timestamp by $writer = $value)';
}

class StoreSnapshot {
  const StoreSnapshot({required this.clock, required this.entries});

  final int clock;
  final List<VersionedEntry> entries;
}

class CommitResult {
  const CommitResult({required this.txn, required this.written});

  /// Transação pronta para o `txn_ok`: leituras preenchidas, escritas ecoadas.
  final List<List<Object?>> txn;

  /// Valores finais publicados por esta transação. Vazio se ela só leu.
  final List<VersionedEntry> written;
}

class Store {
  Store(this.nodeId);

  final String nodeId;

  int _clock = 0;
  final Map<int, VersionedEntry> _data = {};

  int get clock => _clock;

  int? valueOf(int key) => _data[key]?.value;

  String? writerOf(int key) => _data[key]?.writer;

  int? timestampOf(int key) => _data[key]?.timestamp;

  /// Aplica [txn] no estado local e commita antes de devolver.
  ///
  /// Leituras no meio da transação enxergam as escritas anteriores dela.
  /// As outras réplicas só recebem o valor final de cada chave.
  CommitResult commit(List<List<Object?>> txn) {
    final overlay = <int, int>{};
    final completed = <List<Object?>>[];

    for (final op in txn) {
      if (op.length != 3 || op[0] is! String) {
        throw FormatException('operação inválida: $op');
      }
      final kind = op[0] as String;
      final key = _asInt(op[1]);
      if (kind == 'r') {
        final value = overlay.containsKey(key)
            ? overlay[key]
            : _data[key]?.value;
        completed.add(['r', key, value]);
      } else if (kind == 'w') {
        final value = _asInt(op[2]);
        overlay[key] = value;
        completed.add(['w', key, value]);
      } else {
        throw FormatException('operação desconhecida: $kind');
      }
    }

    if (overlay.isEmpty) {
      return CommitResult(txn: completed, written: const []);
    }

    _clock += 1;
    final timestamp = _clock;
    final written = <VersionedEntry>[];
    for (final entry in overlay.entries) {
      final versioned = VersionedEntry(
        key: entry.key,
        timestamp: timestamp,
        writer: nodeId,
        value: entry.value,
      );
      _data[entry.key] = versioned;
      written.add(versioned);
    }
    return CommitResult(txn: completed, written: written);
  }

  /// Funde um gossip. Versão antiga, duplicada ou empatada não substitui a atual.
  ///
  /// O relógio local avança até o relógio remoto para a próxima escrita
  /// ficar depois de tudo o que este nó já observou.
  void merge(int remoteClock, List<VersionedEntry> entries) {
    if (remoteClock > _clock) _clock = remoteClock;
    for (final entry in entries) {
      if (entry.timestamp > _clock) _clock = entry.timestamp;
      final current = _data[entry.key];
      if (current == null || entry.winsOver(current)) {
        _data[entry.key] = entry;
      }
    }
  }

  StoreSnapshot snapshot() {
    return StoreSnapshot(
      clock: _clock,
      entries: List<VersionedEntry>.unmodifiable(_data.values),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('inteiro esperado, recebi $value');
}
