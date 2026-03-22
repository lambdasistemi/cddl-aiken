{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        ghc = pkgs.haskell.packages.ghc966;
        hsPkgs = ghc.override {
          overrides = _hfinal: _hprev: { };
        };
        devTools = [
          pkgs.just
          pkgs.cabal-install
          pkgs.hlint
          hsPkgs.fourmolu
        ];
      in
      {
        devShells.default = hsPkgs.shellFor {
          packages = _: [ ];
          nativeBuildInputs = devTools ++ [
            hsPkgs.ghc
          ];
        };
      }
    );
}
