# CDDL Reference

cddl-aiken supports a JSON-oriented subset of [CDDL (RFC 8610)](https://datatracker.ietf.org/doc/html/rfc8610). Every schema must define two top-level rules: `key` and `value`.

## Primitive types

| CDDL type | CBOR major type | Description |
|-----------|----------------|-------------|
| `uint`    | 0              | Unsigned integer |
| `int`     | 0 or 1         | Signed integer |
| `bstr`    | 2              | Byte string |
| `tstr`    | 3              | Text string (UTF-8) |
| `bool`    | 7              | Boolean |
| `null`    | 7              | Null |

## Maps

Maps use text keys (JSON-style):

```cddl
value = {
  "name"    : tstr,
  "balance" : uint
}
```

Map keys are validated in **canonical CBOR order** (RFC 7049 §3.9) — shorter keys first, then lexicographic. The compiler sorts keys automatically; the CDDL source order doesn't matter.

## Arrays

Fixed-size positional arrays:

```cddl
value = [ uint, tstr, bstr ]
```

The generated validator checks that the array has exactly the declared number of elements and validates each in order.

## Choices

Union types via `/`:

```cddl
value = uint / tstr / null
```

The validator tries each alternative in order and accepts the first match.

## Occurrence indicators

Control field cardinality in maps:

| Indicator | Meaning | Map count effect |
|-----------|---------|-----------------|
| _(none)_  | Required (exactly 1) | must be present |
| `?`       | Optional (0 or 1) | may be absent |
| `*`       | Zero or more | may be absent |
| `+`       | One or more | must be present |

```cddl
value = {
  "required" : uint,
  ? "optional" : tstr,
  * "repeated" : bstr
}
```

## Constraints

### Integer constraints

```cddl
value = {
  "age"     : uint .le 150,
  "balance" : int .ge 0,
  "code"    : uint .eq 42
}
```

| Constraint | Generated check |
|-----------|----------------|
| `.le N`   | `expect v <= N` |
| `.ge N`   | `expect v >= N` |
| `.eq N`   | `expect v == N` |

### Size constraints

For byte strings and text strings:

```cddl
key = {
  "hash"  : bstr .size 32,
  "name"  : tstr .size (1..64)
}
```

| Constraint | Generated check |
|-----------|----------------|
| `.size N`       | `expect length == N` |
| `.size (N..M)`  | `expect length >= N` and `expect length <= M` |

## Named rules

Rules can reference other rules:

```cddl
key = { "owner" : address }
value = { "amount" : uint }

address = bstr .size 28
```

## Comments

Lines starting with `;` are comments:

```cddl
; This is a comment
key = { "owner" : bstr .size 28 }
```

## Unsupported features

The following CDDL features are **not** supported:

- CBOR tags (`#6.N(type)`)
- Floating point types
- Generics, sockets, plugs
- `.cbor` / `.cborseq` / `.regexp` controls
- Indefinite-length encodings
- Integer keys in maps
