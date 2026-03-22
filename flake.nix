{
  inputs = {
    cardano-node-clients = {
      url = "github:lambdasistemi/cardano-node-clients";
    };
    haskellNix.follows = "cardano-node-clients/haskellNix";
    nixpkgs.follows = "cardano-node-clients/nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    iohkNix.follows = "cardano-node-clients/iohkNix";
    CHaP.follows = "cardano-node-clients/CHaP";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, haskellNix, iohkNix, CHaP
    , cardano-node-clients, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      perSystem = { system, ... }:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              iohkNix.overlays.crypto
              haskellNix.overlay
              iohkNix.overlays.haskell-nix-crypto
              iohkNix.overlays.cardano-lib
            ];
          };
          cardano-node-pkgs = cardano-node-clients.inputs.cardano-node.packages.${system};
          devnet-genesis = cardano-node-clients.packages.${system}.devnet-genesis;
          project = pkgs.haskell-nix.cabalProject' {
            src = ./.;
            compiler-nix-name = "ghc984";
            inputMap = {
              "https://chap.intersectmbo.org/" = CHaP;
            };
            shell = {
              tools = {
                cabal = "latest";
                fourmolu = "latest";
                hlint = "latest";
              };
              buildInputs = [
                pkgs.just
                pkgs.curl
                pkgs.cacert
                cardano-node-pkgs.cardano-node
              ];
              shellHook = ''
                export E2E_GENESIS_DIR="${devnet-genesis}"
              '';
            };
          };
        in
        {
          devShells.default = project.shell;
        };
    };
}
