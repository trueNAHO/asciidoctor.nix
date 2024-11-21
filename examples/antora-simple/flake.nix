{
  description = "Simple Asciidoctor Example Based on Antora's Structure";
  inputs.asciidoctor-nix.url = "github:trueNAHO/asciidoctor.nix";

  outputs = inputs:
    inputs.asciidoctor-nix.mkOutputs {
      packages = {
        inherit (inputs.self) lastModified;

        inputFile = "pages/index.adoc";
        src = ./src;
      };
    };
}
