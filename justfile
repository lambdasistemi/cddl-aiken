default:
  @just --list

build:
  cabal build all -O0

test:
  cabal test unit-tests -O0 --test-show-details=direct

format:
  fourmolu -i app/ src/ test/

format-check:
  fourmolu -m check app/ src/ test/

hlint:
  hlint app/ src/ test/

ci: format-check hlint build test

clean:
  cabal clean
