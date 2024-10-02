{
  description = "Simple example";
  inputs.asciidoctor-nix.url = "path:../..";

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
    // inputs.asciidoctor-nix.inputs.flake-utils.lib.eachDefaultSystem (
      system: {
        packages =
          inputs.asciidoctor-nix.inputs.nixpkgs.legacyPackages.${system}.lib.attrsets.unionOfDisjoint
          (inputs.asciidoctor-nix.lib.${system}.packages {src = ./src;})
          (inputs.asciidoctor-nix.packages.${system} or {});
      }
    );
}
