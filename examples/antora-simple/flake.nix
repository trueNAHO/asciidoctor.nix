{
  description = "Simple example based on Antora's structure";

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
        packages = inputs.asciidoctor-nix.lib.${system}.packages {
          inputFile = "pages/index.adoc";
          src = ./src;
        };
      }
    );
}
