{
  description = "Simple example";

  inputs = {
    asciidoctor-nix.url = "github:trueNAHO/asciidoctor.nix";
    flake-utils.follows = "asciidoctor-nix/flake-utils";
    nixpkgs.follows = "asciidoctor-nix/nixpkgs";
  };

  outputs = inputs:
    builtins.removeAttrs inputs.asciidoctor-nix [
      "_type"
      "inputs"
      "lastModified"
      "lastModifiedDate"
      "lib"
      "narHash"
      "outPath"
      "outputs"
      "packages"
      "sourceInfo"
    ]
    // inputs.flake-utils.lib.eachDefaultSystem (
      system: {
        packages =
          inputs.nixpkgs.legacyPackages.${system}.lib.attrsets.unionOfDisjoint
          (inputs.asciidoctor-nix.lib.${system}.packages {src = ./src;})
          (inputs.asciidoctor-nix.packages.${system} or {});
      }
    );
}
