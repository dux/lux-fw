> STATUS: design proposal - NOT implemented. Describes a possible local-first
> sync engine for Lux + Svelte, not current behavior.

# Svelte sync engine idea

## Why

The standard web model is *fetch-per-view*: every screen calls an endpoint,
maps the response into local state, and re-fetches when something might have
changed. Reads are scattered across the app, optimistic updates are written
by hand per mutation, and "is this list stale?" is a question you answer over
and over.

The local-first / sync-engine model (Linear, Replicache, Zero) flips it:

* The client holds a **local store** that mirrors the data it cares about.
* A **sync engine** keeps that store in step with the server over a socket,
  pushing changes as they happen.
* App code **only ever reads and writes local state**. There is no
  `fetch('/api/todos')` anywhere in a feature. You define **queries over local
  sets**, and those results are **reactive** — when the engine applies a
  change, anything observing that set re-renders.

We want this on our own stack: **Lux** on the server (`lux-fw` + a thin
`lux-api` sync layer), **Svelte 5** on the client, and our existing pieces
(`json-exporter`, `egoist`, `typero`, `postwind`) doing the work they already
do. We can use something ready, but the core is a weekend of code and we
understand every line — so we write it.

## Mental model

Four pieces, that is the whole thing:

```
┌─────────────── CLIENT (Svelte) ───────────────┐         ┌────────── SERVER (Lux) ──────────┐
│                                                │         │                                  │
│  Components ─read─> Reactive queries ($derived) │        │   lux-api  (WS handler)          │
│       │                     ▲                   │ socket  │      │                           │
│       │ write (mutator)     │                   │ <─────> │   Mutators (authoritative)       │
│       ▼                     │                   │ deltas  │      │                           │
│  Local store ($state Map) ──┘                   │         │   Postgres (truth + sync_log)    │
│       │                                         │         │      │                           │
│  IndexedDB (persist + offline queue)            │         │   LISTEN/NOTIFY fan-out          │
└────────────────────────────────────────────────┘         └──────────────────────────────────┘
```

1. **Local store** — in-memory `Map` per collection, wrapped in Svelte 5
   `$state`.
2. **Reactive queries** — `$derived` views over the store = the
   "auto-updatable sets".
3. **Sync transport** — one WebSocket, cursor-based resume, applies changes to
   the store.
4. **Mutators** — named writes that apply optimistically on the client and
   authoritatively on the server.

## The unit of sync: exported objects

The engine **never sees raw DB rows**. It only ever works with **exported
objects** — whatever `json-exporter` produces for a class. The unit of sync is
**one exported object**, identified by `(class, ref)`, and the update semantics
are **whole-object replace** (not field patches).

This matches every serious normalized cache (Apollo/Relay key by
`__typename:id`, Linear keys by model+id). The same envelope is used for
bootstrap, live update, mutation result, and reconnect catch-up:

```json
{
  "class": "Todo",
  "ref":   "Todo#01H8X...",   // globally unique identity
  "v":     412,               // per-object version (monotonic)
  "data":  { ...exported fields... },
  "deleted": false
}
```

* `class` routes the object to a local collection.
* `ref` is the upsert key.
* `v` decides who wins (highest version).
* `deleted: true` is a tombstone.

### The entire client apply logic is ~6 lines

Because the unit is a whole object keyed by `(class, ref)` with a version,
applying any inbound message is trivial and **idempotent / order-independent**:

```js
function apply(obj) {
  const col = registry[obj.class];                 // class -> local collection
  if (obj.deleted)            col.remove(obj.ref);
  else if ((col.get(obj.ref)?.v ?? -1) < obj.v)    // keep highest version
                              col.upsert(obj.ref, obj);
}
```

Bootstrap, live delta, optimistic mutation, reconnect catch-up — **all the same
function**. A late or duplicate publish with an older `v` is simply dropped.

### Relations are refs, resolved locally

The payoff of `class/ref`: an exported object links to others **by ref**, not by
nesting. The client resolves refs against the local store → a normalized object
graph, and joins become reactive for free:

```svelte
const todo    = $derived(db.Todo.get(ref));
const project = $derived(db.Project.get(todo.project));   // republishes → view updates
```

So **size exported objects as the natural sync unit**: link by ref, do not nest.
If something is huge (a doc + its blocks), split it into separate classes so one
edit does not resend the whole thing.

## Frontend: the Svelte sync engine

Svelte 5 runes are a perfect fit — better than React here. Runes work in plain
`.svelte.js` modules, so the store lives outside components and components just
observe it.

```js
// store.svelte.js
class Collection {
  #rows = $state(new Map());          // ref -> record

  upsert(ref, r) { this.#rows.set(ref, r); }
  remove(ref)    { this.#rows.delete(ref); }
  get(ref)       { return this.#rows.get(ref); }

  get all() { return [...this.#rows.values()]; }
  where(fn) { return this.all.filter(fn); }   // call inside $derived in a component
}
```

```svelte
<script>
  import { db } from './store.svelte.js';
  // auto-updates whenever sync applies a change — no fetch anywhere
  const open = $derived(db.Todo.where(t => !t.done));
</script>
```

The client lib has four sub-parts:

* **Store** — the `$state` Maps above, one `Collection` per class, plus the
  `registry` (`class` → collection).
* **Transport** — WS connect/reconnect, sends cursor on open, runs `apply` on
  every inbound object.
* **Persistence** — IndexedDB adapter: hydrate the store on cold start, persist
  the offline mutation queue. Hand-rolled (~150 lines) or `idb`.
* **Mutator registry** — `db.mutate.addTodo({...})` → apply optimistically to
  the store, enqueue, send.

## Backend: lux-api

Postgres is the source of truth. The one idea that makes sync simple is a
**global changelog with a monotonic cursor**:

```sql
create table sync_log (
  seq        bigserial primary key,  -- the cursor clients track; also serves as object `v`
  class      text  not null,
  ref        text  not null,
  op         smallint not null,      -- 0 = upsert, 1 = delete
  data       jsonb,                  -- exported object snapshot (null on delete)
  actor_id   uuid,
  created_at timestamptz default now()
);
```

* Every mutator writes the row **and** appends to `sync_log` in the same
  transaction.
* The append stores the **exported** object (`json-exporter` output), never the
  raw row.
* Client stores the last `seq` it has seen.
* **Live** = `NOTIFY` on insert; the WS process is `LISTEN`-ing and pushes new
  rows to subscribed clients.

Using `seq` as both the resume cursor **and** the per-object `v` means one
number does double duty — clients keep the highest `seq` per ref, and the
global max `seq` is the reconnect cursor.

**Ruby stack:** [Falcon](https://github.com/socketry/falcon) (async, handles
thousands of idle WS connections far better than Puma) + Postgres
`LISTEN/NOTIFY` for multi-process fan-out. No Redis needed until presence/scale.

## Initial load: "fetch" happens once, generically

"Never fetch" means **app code** never fetches. The **sync engine** does it
once, for you. The initial load is just **catch-up from cursor 0** — the same
mechanism, parameterized by an empty cursor. No per-view endpoints; one generic
bootstrap.

**Cold start** (empty IndexedDB):

```
1. GET /sync/bootstrap            → snapshot of every object you may see
                                     + current max seq (your starting cursor)
2. load snapshot into the store (run `apply` on each)
3. open WS, send hello {cursor}   → server streams changes from there on
```

**Warm start** (returning client — the common case):

```
1. hydrate store from IndexedDB   → instant, zero network, works offline
2. open WS, send hello {cursor:N} → server sends ONLY what changed since N
```

### The gotcha: snapshot ≠ changelog

* **Bootstrap snapshot** comes from the *real tables*, exported:
  `Todo.visible_to(user).map { Export::Todo.call(_1) }`. Current state, one
  object per record.
* **Deltas** come from `sync_log`. That is a *change* log — do **not** replay it
  from seq 0 to build initial state.

Read current tables for the base, then tail the log for changes. The cursor
stitches them: the snapshot says "current as of seq N", the WS picks up at N+1.

### Channel split

| Phase             | Channel    | Why                              |
|-------------------|------------|----------------------------------|
| Bootstrap snapshot| HTTP GET   | Big, one-shot, gzippable, cacheable |
| Live deltas       | WebSocket  | Small, continuous, low-latency   |

## Protocol (4 messages)

| Direction | Message                                | Meaning                                   |
|-----------|----------------------------------------|-------------------------------------------|
| C→S       | `hello {cursor, classes}`              | "I'm at seq N, sync me these classes"     |
| S→C       | `obj {class, ref, v, data, deleted}`   | apply this object (the envelope above)    |
| C→S       | `mutate {id, name, args}`              | run this named mutation                   |
| S→C       | `ack {mutationId, seq}`                | confirmed; drop the optimistic version    |

That is a complete, resumable sync engine.

## Mutation round-trip

```
1. client: db.mutate.addTodo({title})
2. client: build optimistic exported object {class:'Todo', ref:tempRef, v:∞, data}
           → apply() locally (instant UI), enqueue, send mutate{...}
3. server: run authoritative mutator in a txn
           → write row, append sync_log (exported), assign real ref + seq
4. server: broadcast obj{...} (authoritative) + ack{mutationId, seq}
5. client: on ack, drop the optimistic temp object; authoritative obj replaces it
```

Because the server publishes the **re-exported server object** — not the
client's guess — every client converges to identical server truth, even under
concurrent edits. The only thing whole-object LWW gives up is *field-level*
merge (two people editing different fields of the same object in the same
instant → last publish wins). Fine unless we want collaborative text editing,
which is the one case that pushes toward CRDTs.

## Why the exporter being the boundary is the real win

Because the engine *only* ever sees exported objects, `json-exporter` becomes
the **single source of truth** for three things at once:

* the **wire schema** (field shape),
* the **permission / shaping filter** — only export what the user may see, pair
  with `egoist`,
* and it produces **both** the bootstrap snapshot **and** every live publish —
  *same code path*, so they cannot drift.

One exporter per class, used everywhere. That is the thing that keeps a
hand-rolled sync engine from rotting. Bootstrap "what you can load" and live
"what you can receive" run through the **same `egoist` policy**, so they are
guaranteed consistent.

## What collapses

The whole REST sprawl reduces to two things:

```
Reads:   GET /sync/bootstrap   +   WS obj stream     (all reads, every class)
Writes:  mutate {name, args}   over WS               (all writes, every class)
```

No endpoint-per-view. No hand-written optimistic update per mutation.

## Build vs. buy

Write it ourselves, but **steal the design** from Replicache's published model
(mutators + cursor + poke/pull) rather than inventing a protocol. The hard parts
are narrow — decide them consciously:

* **Conflict resolution** — server-authoritative + last-write-wins per object to
  start. Only reach for CRDTs (Yjs/Automerge) if we need collaborative *text*
  editing.
* **Partial sync + permissions** — "whole datasets locally" is great until a
  dataset is big or not all of it is yours to see. Filter both bootstrap and
  `sync_log` per user with `egoist`. **This is the single most important thing
  to design early.**
* **Optimistic write reconciliation** — simplest version: client does generic
  optimistic upsert; on `ack` the authoritative exported object overwrites it.
  Avoid mirroring full mutator *logic* on both sides until actually needed.

## Mapping to our stack

| Concern                  | Use                                          |
|--------------------------|----------------------------------------------|
| Reactive client store    | **Svelte 5 runes** (`$state` / `$derived`)   |
| Wire schema + snapshot   | **json-exporter** (the contract)             |
| Read permissions on sync | **egoist**                                   |
| Schema / mutator types   | **typero** — define once, generate client types |
| Async WS server          | **Falcon** + Postgres `LISTEN/NOTIFY`        |
| Client persistence       | hand-rolled IndexedDB wrapper, or `idb`      |
| Styling                  | **postwind**                                 |
| Navigation               | client-side routing; `dux-pjax` matters less in a local-first SPA |

`fez` is orthogonal here since Svelte owns the view layer — unless we want it for
embeddable widgets outside the app.

## Open decisions

* **Sync scope** — whole datasets per user (simplest), or filtered/partial sync
  from day one (needed if data is big or shared/permissioned)?
* **Conflicts** — server-authoritative LWW (recommended), or real-time
  collaborative editing (→ CRDTs)?
* **ref format** — single global string (`Todo#123`, easy single map key) vs.
  explicit `class` + `id`. Leaning: global string for the key, explicit `class`
  on the envelope so clients never parse refs.

## First milestone

1. `sync_log` + one mutator + the `hello`/`obj` round-trip over WS — one class
   live across two tabs.
2. Add IndexedDB hydrate + offline queue.
3. Add `egoist`-filtered partial sync (bootstrap + deltas through one policy).
4. Then optimistic mutators + rebase on `ack`.
