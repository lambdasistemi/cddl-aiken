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

e2e:
  cabal test cddl-e2e -O0 --test-show-details=direct

ci: format-check hlint build test

build-docs:
  mkdocs build

serve-docs:
  mkdocs serve

deploy-docs:
  mkdocs gh-deploy --force

clean:
  cabal clean
