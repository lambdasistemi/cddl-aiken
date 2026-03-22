# Generated Code

This page walks through what `cddl-aiken compile` produces for a concrete schema.

## Input

```cddl
key = {
  "owner" : bstr .size 28
}

value = {
  "amount"  : uint,
  "payload" : bstr,
  ? "label" : tstr
}
```

## Output files

### `aiken.toml`

```toml
name = "generated/cddl_schema"
version = "0.0.1"
compiler = "v1.1.21"
plutus = "v3"

[repository]
user = "generated"
project = "cddl_schema"
platform = "github"

[[dependencies]]
name = "aiken-lang/stdlib"
version = "v3.0.0"
source = "github"
```

### `lib/cbor.ak`

A self-contained CBOR parsing library. Core type:

```rust
pub type ParseResult<a> {
  value: a,
  pos: Int,
}
```

Provides parsers for all CBOR major types (uint, int, bstr, tstr, bool, null, arrays, maps) plus `skip_value` for advancing past unknown values.

### `validators/schema.ak`

#### `validate_key`

The key schema has one required field `"owner"` of type `bstr .size 28`:

```rust
fn validate_key(bytes: ByteArray, pos: Int) -> Int {
  let ParseResult { value: count, pos } = parse_map_header(bytes, pos)
  expect count == 1

  let ParseResult { value: k0, pos } = parse_tstr(bytes, pos)
  expect k0 == #"6f776e6572"  // "owner"
  let ParseResult { value: v, pos } = parse_bstr(bytes, pos)
  expect builtin.length_of_bytearray(v) == 28
  pos
}
```

#### `validate_value`

The value schema has two required fields and one optional. Keys are sorted canonically: `"amount"` < `"label"` < `"payload"`.

```rust
fn validate_value(bytes: ByteArray, pos: Int) -> Int {
  let ParseResult { value: count, pos } = parse_map_header(bytes, pos)
  expect count >= 2
  expect count <= 3

  // "amount" (required, always first)
  let ParseResult { value: k0, pos } = parse_tstr(bytes, pos)
  expect k0 == #"616d6f756e74"
  let ParseResult { value: _, pos } = parse_uint(bytes, pos)

  // "label" (optional, present only if count > 2)
  let pos = if count > 2 {
    let saved = pos
    let ParseResult { value: k1, pos } = parse_tstr(bytes, pos)
    if k1 == #"6c6162656c" {
      let ParseResult { value: _, pos } = parse_tstr(bytes, pos)
      pos
    } else {
      saved
    }
  } else {
    pos
  }

  // "payload" (required, always last)
  let ParseResult { value: k2, pos } = parse_tstr(bytes, pos)
  expect k2 == #"7061796c6f6164"
  let ParseResult { value: _, pos } = parse_bstr(bytes, pos)
  pos
}
```

#### Withdrawal validator

```rust
validator cddl_schema {
  withdraw(redeemer: Data, _account: Credential, _self: Transaction) {
    expect (key_bytes, value_bytes): (ByteArray, ByteArray) = redeemer
    let key_end = validate_key(key_bytes, 0)
    expect key_end == builtin.length_of_bytearray(key_bytes)
    let value_end = validate_value(value_bytes, 0)
    expect value_end == builtin.length_of_bytearray(value_bytes)
    True
  }
}
```

The validator:

1. Extracts key and value byte arrays from the redeemer
2. Parses each through the schema-specific validation function
3. Asserts that parsing consumed all bytes (no trailing data)
4. Returns `True` if both pass

## Canonical CBOR ordering

Map keys are compared by their CBOR-encoded bytes (RFC 7049 §3.9):

1. Shorter encoded keys come first
2. Same-length keys are compared lexicographically

For text keys this simplifies to: shorter strings first, then alphabetical. The compiler sorts keys at compile time so the validator can match sequentially.

| Key | Hex encoding | Length |
|-----|-------------|--------|
| `"amount"` | `616d6f756e74` | 6 |
| `"label"` | `6c6162656c` | 5 |
| `"payload"` | `7061796c6f6164` | 7 |

Canonical order: `"label"` (5) < `"amount"` (6) < `"payload"` (7).

!!! note
    The CDDL source order doesn't matter. The compiler always emits checks in canonical order.
