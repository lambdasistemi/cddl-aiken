# Getting Started

## Prerequisites

- [Nix](https://nixos.org/) with flakes enabled
- [Aiken](https://aiken-lang.org/) (for building generated projects)

## Setup

```bash
git clone https://github.com/lambdasistemi/cddl-aiken.git
cd cddl-aiken
nix develop
```

The nix shell provides GHC, cabal, fourmolu, hlint, and a local `cardano-node` for E2E testing.

## Build

```bash
just build
```

## Usage

### 1. Write a CDDL schema

Create a `.cddl` file with `key` and `value` rules:

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

Both `key` and `value` must be defined. They describe the shapes of CBOR-encoded data that the withdrawal validator will enforce.

### 2. Compile

```bash
cddl-aiken compile schema.cddl -o output/
```

Output:

```
Generated 3 files in output/
  lib/cbor.ak
  validators/schema.ak
  aiken.toml
```

### 3. Build the Aiken project

```bash
cd output/
aiken build
```

This produces a Plutus blueprint in `plutus.json` containing the compiled validator script.

### 4. Deploy

Extract the compiled code from the blueprint and use it as a withdrawal validator parameterizing your MPFS cage.

## Running tests

```bash
just test           # unit tests
just ci             # full CI pipeline (format, lint, build, test)

# E2E tests (requires cardano-node in nix shell)
cabal test cddl-e2e -O0 --test-show-details=direct
```
