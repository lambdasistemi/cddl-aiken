# cddl-aiken: CDDL to Aiken Withdrawal Validator Compiler

## Problem

MPFS cages store arbitrary key/value pairs as CBOR byte strings.
Without schema enforcement, any request can write any shape of data.
We need on-chain validation that request keys and values conform to a
declared schema — like a JSON Schema but for CBOR on Cardano.

## Architecture

```
                    Oracle (off-chain)
                    ┌─────────────────────────┐
  .cddl file ──────│  cddl-aiken compiler    │
                    │  (Haskell)              │
                    │         │               │
                    │         ▼               │
                    │  Aiken source code      │
                    │         │               │
                    │    aiken build          │
                    │         │               │
                    │         ▼               │
                    │  Plutus script (UPLC)   │
                    └────────┬────────────────┘
                             │
                             ▼ published on-chain
              ┌──────────────────────────────────┐
              │  MPFS Cage Validator              │
              │  (parameterized by script hash)   │
              │                                   │
              │  At mint time:                    │
              │  1. Check withdrawal present      │
              │  2. Withdrawal validator runs     │
              │     → parses request key CBOR     │
              │     → parses request value CBOR   │
              │     → validates structure          │
              │  3. If validator passes → mint ok │
              └──────────────────────────────────┘
```

### Flow

1. Schema author writes a `.cddl` file defining key and value shapes
2. Oracle runs `cddl-aiken` compiler → produces Aiken withdrawal validator source
3. Oracle runs `aiken build` → produces Plutus script
4. Script hash is used to parameterize the MPFS cage validator
5. At mint time, the withdrawal validator is included in the transaction
6. It receives the request's key and value `ByteArray`s
7. It parses the CBOR bytes and validates they match the schema
8. If validation fails, the transaction fails

## CDDL Subset

We target a JSON-like subset of CDDL (RFC 8610):

### Supported Types

| CDDL Type | CBOR Major Type | Description |
|-----------|-----------------|-------------|
| `uint`    | 0               | Unsigned integer |
| `int`     | 0, 1            | Signed integer |
| `tstr`    | 3               | Text string (UTF-8) |
| `bstr`    | 2               | Byte string |
| `bool`    | 7 (20, 21)      | Boolean |
| `null`    | 7 (22)          | Null |

### Supported Structures

**Maps with named keys** (the core use case):

```cddl
request-key = {
  "owner" : bstr,
  "slot"  : uint
}

request-value = {
  "amount"  : uint,
  "payload" : bstr,
  ? "memo"  : tstr
}
```

Key names are text strings and must match exactly. This is the
JSON-Schema-like property: known keys, typed values.

**Arrays** (positional):

```cddl
point = [uint, uint]
```

**Choices**:

```cddl
action = "insert" / "delete" / "update"
```

**Occurrence indicators**:

| Indicator | Meaning |
|-----------|---------|
| (none)    | Exactly 1 (required) |
| `?`       | 0 or 1 (optional) |
| `*`       | 0 or more |
| `+`       | 1 or more |

**Semantic constraints**:

```cddl
; Value ranges
age = uint .le 150

; Size constraints
hash = bstr .size 32
name = tstr .size (1..64)
```

### NOT Supported

- Tags (`#6.N(type)`)
- Floating point
- Generics
- Sockets/plugs
- `.cbor` / `.cborseq` controls
- `.regexp`
- Nested CBOR (CBOR-in-CBOR beyond the top level)

## Compiler Design

### Input

A `.cddl` file with two top-level rules: `key` and `value`.

```cddl
key = {
  "owner" : bstr .size 28
}

value = {
  "amount"   : uint,
  "payload"  : bstr,
  ? "label"  : tstr
}
```

### Output

An Aiken project containing a withdrawal validator that:

1. Receives key and value as `ByteArray` via the redeemer
2. Parses CBOR bytes
3. Validates structure and constraints
4. Fails via `expect` on any mismatch

### Haskell Pipeline

```
Parse CDDL          →  CDDL AST
                         │
Validate subset      →  Reject unsupported features
                         │
Lower to IR          →  CborSchema (internal representation)
                         │
Generate Aiken       →  Aiken source text
```

### Internal Representation

```haskell
data CborSchema
  = CUint (Maybe Constraint)
  | CInt (Maybe Constraint)
  | CTstr (Maybe SizeConstraint)
  | CBstr (Maybe SizeConstraint)
  | CBool
  | CNull
  | CMap [(Key, Occurrence, CborSchema)]
  | CArray [CborSchema]
  | CChoice [CborSchema]

data Key
  = TextKey Text    -- named map key (the common case)

data Occurrence
  = Required        -- exactly 1
  | Optional        -- ? (0 or 1)
  | ZeroOrMore      -- *
  | OneOrMore       -- +

data Constraint
  = Le Integer
  | Ge Integer
  | Range Integer Integer

data SizeConstraint
  = ExactSize Integer
  | SizeRange Integer Integer
```

## Generated Aiken Structure

### CBOR Parsing Library

The compiler emits a small CBOR parsing library alongside the
validator. This library operates on `ByteArray` and tracks a
cursor position.

Core operations:

```aiken
/// Parse result: decoded value + remaining bytes position
type ParseResult<a> {
  value: a,
  pos: Int,
}

/// Read CBOR major type and argument from bytes at position
fn read_header(bytes: ByteArray, pos: Int) -> ParseResult<(Int, Int)>

/// Parse unsigned integer
fn parse_uint(bytes: ByteArray, pos: Int) -> ParseResult<Int>

/// Parse text string
fn parse_tstr(bytes: ByteArray, pos: Int) -> ParseResult<ByteArray>

/// Parse byte string
fn parse_bstr(bytes: ByteArray, pos: Int) -> ParseResult<ByteArray>

/// Parse bool
fn parse_bool(bytes: ByteArray, pos: Int) -> ParseResult<Bool>

/// Assert major type matches, fail otherwise
fn expect_major(bytes: ByteArray, pos: Int, expected: Int) -> ParseResult<Int>

/// Parse map header, return number of entries
fn parse_map_header(bytes: ByteArray, pos: Int) -> ParseResult<Int>

/// Parse array header, return number of elements
fn parse_array_header(bytes: ByteArray, pos: Int) -> ParseResult<Int>
```

### Generated Validator Shape

For the example CDDL above, the compiler generates:

```aiken
use aiken/collection/list

validator cddl_validator {
  withdraw(_redeemer: Data, _ctx: Data) {
    // Redeemer contains: (key_bytes, value_bytes)
    expect (key_bytes, value_bytes): (ByteArray, ByteArray) = _redeemer

    // Validate key
    let key_end = validate_key(key_bytes, 0)
    expect key_end == builtin.length_of_bytearray(key_bytes)

    // Validate value
    let value_end = validate_value(value_bytes, 0)
    expect value_end == builtin.length_of_bytearray(value_bytes)

    True
  }
}

fn validate_key(bytes: ByteArray, pos: Int) -> Int {
  // Expect map with 1 entry
  let ParseResult { value: count, pos } = parse_map_header(bytes, pos)
  expect count == 1

  // Key "owner" : bstr .size 28
  let ParseResult { value: key_name, pos } = parse_tstr(bytes, pos)
  expect key_name == "owner"
  let ParseResult { value: owner, pos } = parse_bstr(bytes, pos)
  expect builtin.length_of_bytearray(owner) == 28

  pos
}

fn validate_value(bytes: ByteArray, pos: Int) -> Int {
  // Expect map with 2-3 entries (label is optional)
  let ParseResult { value: count, pos } = parse_map_header(bytes, pos)
  expect count >= 2
  expect count <= 3

  // Parse entries by iterating and matching keys
  // (order may vary in CBOR maps)
  validate_value_entries(bytes, pos, count, False, False, False)
}
```

### Map Key Ordering

CBOR maps don't guarantee key order. The generated validator must
handle any key permutation. Strategy: iterate entries, match each
key by name, track which required keys were seen:

```aiken
fn validate_value_entries(
  bytes: ByteArray,
  pos: Int,
  remaining: Int,
  seen_amount: Bool,
  seen_payload: Bool,
  seen_label: Bool,
) -> Int {
  if remaining == 0 {
    // Check all required keys were present
    expect seen_amount
    expect seen_payload
    pos
  } else {
    let ParseResult { value: key_name, pos } = parse_tstr(bytes, pos)
    if key_name == "amount" {
      expect !seen_amount  // no duplicates
      let ParseResult { pos, .. } = parse_uint(bytes, pos)
      validate_value_entries(bytes, pos, remaining - 1, True, seen_payload, seen_label)
    } else if key_name == "payload" {
      expect !seen_payload
      let ParseResult { pos, .. } = parse_bstr(bytes, pos)
      validate_value_entries(bytes, pos, remaining - 1, seen_amount, True, seen_label)
    } else if key_name == "label" {
      expect !seen_label
      let ParseResult { pos, .. } = parse_tstr(bytes, pos)
      validate_value_entries(bytes, pos, remaining - 1, seen_amount, seen_payload, True)
    } else {
      fail @"unexpected key"
    }
  }
}
```

## CBOR Encoding Reference

For the parsing library, the relevant CBOR encoding (RFC 7049):

| Major Type | Value | Encoding |
|------------|-------|----------|
| 0 | Unsigned int | `0x00`–`0x17` (0–23 inline), `0x18` + 1 byte, `0x19` + 2 bytes, `0x1a` + 4 bytes, `0x1b` + 8 bytes |
| 1 | Negative int | Same additional info encoding as type 0, value = -1 - arg |
| 2 | Byte string | Length-prefixed (same encoding as int for length) |
| 3 | Text string | Length-prefixed (same encoding as int for length) |
| 4 | Array | Count-prefixed |
| 5 | Map | Count-prefixed (count = number of key-value pairs) |
| 7 | Simple | `0xf4` = false, `0xf5` = true, `0xf6` = null |

## Open Questions

1. **Redeemer shape**: Is the withdrawal redeemer `(key_bytes, value_bytes)` or something else?  Depends on how the MPFS cage validator passes data.

2. **Canonical CBOR**: Should we require deterministic/canonical CBOR encoding (sorted map keys)? If yes, validation is simpler — we can expect keys in lexicographic order instead of handling permutations.

3. **Error reporting**: On-chain we just fail. Should the generated code include trace messages for debugging? (costs budget)

4. **Multiple schemas**: One CDDL file per cage, or support multiple key/value schema pairs?

5. **Script size budget**: On-chain CBOR parsing is expensive. Need to profile generated validators to ensure they fit within transaction limits.

## Implementation Plan

### Phase 1: CBOR Parsing Library (Aiken)

Write and test the base CBOR parsing library in Aiken. This is
reusable across all generated validators.

### Phase 2: Haskell CDDL Parser

Parse the JSON-like CDDL subset into the internal `CborSchema` IR.
Either use an existing library or write a minimal parser.

### Phase 3: Aiken Code Generator

Haskell module that takes `CborSchema` and emits Aiken source code.
Produces a complete Aiken project (source + `aiken.toml`).

### Phase 4: CLI

Command-line tool: `cddl-aiken compile schema.cddl -o output/`

### Phase 5: Integration with MPFS

Wire up with the cage validator parameterization. Test end-to-end
with a real cage.
