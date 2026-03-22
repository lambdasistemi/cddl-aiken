# cddl-aiken

CDDL to Aiken withdrawal validator compiler for on-chain CBOR schema enforcement on Cardano.

## Overview

Compiles [CDDL](https://datatracker.ietf.org/doc/html/rfc8610) schema definitions into [Aiken](https://aiken-lang.org/) withdrawal validators that validate CBOR data at mint time in MPFS cages.

## Quick start

```bash
nix develop
cddl-aiken compile examples/cage-request.cddl -o output/
cd output/ && aiken build
```

## Documentation

Full documentation: [lambdasistemi.github.io/cddl-aiken](https://lambdasistemi.github.io/cddl-aiken/)

- [Getting Started](https://lambdasistemi.github.io/cddl-aiken/getting-started/)
- [CDDL Reference](https://lambdasistemi.github.io/cddl-aiken/cddl-reference/)
- [Architecture](https://lambdasistemi.github.io/cddl-aiken/architecture/)
- [Generated Code](https://lambdasistemi.github.io/cddl-aiken/generated-code/)
- [E2E Testing](https://lambdasistemi.github.io/cddl-aiken/e2e-testing/)

## License

Apache-2.0
