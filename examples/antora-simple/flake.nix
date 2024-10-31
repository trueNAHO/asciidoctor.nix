{
  description = "Simple Asciidoctor Example Based on Antora's Structure";

  inputs = {
    asciidoctor-nix.url = "github:trueNAHO/asciidoctor.nix";
    flake-utils.follows = "asciidoctor-nix/flake-utils";
    nixpkgs.follows = "asciidoctor-nix/nixpkgs";
  };

  outputs = inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system:
        inputs.asciidoctor-nix.mkOutputs.${system} (
          parent: {
            packages = parent.packages {
              inputFile = "pages/index.adoc";
              src = ./src;
            };
          }
        )
    );
}
