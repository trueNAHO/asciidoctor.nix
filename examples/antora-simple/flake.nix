{
  description = "Simple Asciidoctor Example Based on Antora's Structure";
  inputs.asciidoctor-nix.url = "github:trueNAHO/asciidoctor.nix";

  outputs = inputs:
    inputs.asciidoctor-nix.mkOutputs (
      outputs: {
        packages = outputs.packages {
          inputFile = "pages/index.adoc";
          src = ./src;
        };
      }
    );
}
