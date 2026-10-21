# SDUI Mutable State Sync
20-minute AI-assisted interview challenge with Maelstrom `txn-rw-register`

## What this challenge is

You may use AI, documentation, web search, and any programming language.

Maelstrom is a small distributed-systems test harness. It starts your program as one or more nodes, sends JSON messages to stdin, expects JSON replies on stdout, can simulate network partitions, and checks whether the observed behavior matches a consistency model.

Maelstrom is **not expected to be installed**. Part of the challenge is using AI to set it up quickly, understand the protocol, implement a small node, and run the tests.

You are building the node binary passed to `--bin`. In the examples below that binary is `~/go/bin/maelstrom-txn`, but it can be written in any language.

This challenge uses only Maelstrom's `txn-rw-register` workload: transactions made of reads and writes over integer keys. Think of each key as mutable SDUI state: manifest version, UI fragment version, rollout config, feature flag, or rollback target.

We are evaluating whether you can:

- learn an unfamiliar distributed-systems tool quickly;
- implement a small read/write register;
- reason about retries, duplicates, stale reads, and partitions;
- explain your consistency and availability tradeoffs.

## Timebox and levels

The 20-minute target is **Level 1** and a good attempt at **Level 2**.

- **Level 1:** single node, local transactions.
- **Level 2:** two nodes, no partitions.
- **Level 3:** two nodes, partitions, total availability.
- **Level 4:** hard mode: stronger consistency under partitions.

Do not try to solve everything first. Pass Level 1, then improve.

## Mission

1. Implement a Maelstrom node for `txn-rw-register`.
2. Keep protocol JSON on stdout only. Logs go to stderr only.
3. Reply to `init` with `init_ok`.
4. Reply to `txn` with `txn_ok`.
5. Fill read operations with the value your node returns.
6. Echo write operations unchanged.
7. Be ready to explain what your system guarantees.

## How Maelstrom talks to your program

Your program is a long-running process. Maelstrom writes one JSON message per line to stdin. Your program writes one JSON message per line to stdout.

Example loop:

```text
for each line from stdin:
  parse JSON
  update local state
  print JSON reply to stdout
```

Important: stdout must contain only protocol JSON. Put debug logs on stderr.

## Protocol summary

### Init

Request:

```json
{"src":"c1","dest":"n1","body":{"type":"init","node_id":"n1","node_ids":["n1","n2"],"msg_id":1}}
```

Reply:

```json
{"src":"n1","dest":"c1","body":{"type":"init_ok","in_reply_to":1}}
```

### Transaction

Request:

```json
{"src":"c1","dest":"n1","body":{"type":"txn","msg_id":2,"txn":[["r",1,null],["w",1,42],["r",1,null]]}}
```

Reply:

```json
{"src":"n1","dest":"c1","body":{"type":"txn_ok","in_reply_to":2,"txn":[["r",1,null],["w",1,42],["r",1,42]]}}
```

Operations:

```text
["r", key, null]   read key
["w", key, value]  write value to key
```

For a single node, a simple map is enough:

```text
key -> value
```

Process operations in order. A write should affect later reads in the same transaction.

## Level 1 — Single node

```bash
./maelstrom test -w txn-rw-register --bin ~/go/bin/maelstrom-txn --node-count 1 --time-limit 20 --rate 1000 --concurrency 2n --consistency-models read-uncommitted --availability total
```

Goal:

- handle `init`;
- handle `txn`;
- keep local register state;
- return valid `txn_ok` for every request.

## Level 2 — Two nodes, no partitions

```bash
./maelstrom test -w txn-rw-register --bin ~/go/bin/maelstrom-txn --node-count 2 --concurrency 2n --time-limit 20 --rate 1000 --consistency-models read-uncommitted
```

Goal:

- make replicas share writes;
- handle duplicate or reordered internal messages safely;
- explain what a read can return before replicas agree.

You may use any simple replication strategy: forward writes, gossip state, or choose a coordinator.

## Level 3 — Partitions and total availability

```bash
./maelstrom test -w txn-rw-register --bin ~/go/bin/maelstrom-txn --node-count 2 --concurrency 2n --time-limit 20 --rate 1000 --consistency-models read-uncommitted --availability total --nemesis partition
```

Goal:

- keep replying during partitions;
- converge after partitions heal;
- explain how concurrent writes to the same key are resolved.

A common approach is to attach a version to each value and merge deterministically, for example:

```text
key -> (timestamp, node_id, value)
```

## Level 4 — Hard mode

```bash
./maelstrom test -w txn-rw-register --bin ~/go/bin/maelstrom-txn --node-count 2 --concurrency 2n --time-limit 20 --rate 1000 --consistency-models read-committed --availability total --nemesis partition
```

Goal:

- attempt stronger semantics;
- if it does not pass, explain what prevents total availability and stronger consistency from coexisting under partitions.

## Success criteria

### Minimum

- Maelstrom runs.
- Level 1 passes or is very close.
- You can explain your local state and transaction handling.

### Strong

- Level 2 passes or is close.
- Your design handles retries, duplicates, and reordered messages safely.
- You can explain stale reads.

### Excellent

- Level 3 passes reliably.
- Your node remains available during partitions.
- Replicas converge after healing.
- You can explain the tradeoff you chose.

Have fun!
