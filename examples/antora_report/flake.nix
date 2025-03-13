{
  description = "Antora example with report";
  inputs.asciidoctor-nix.url = "github:trueNAHO/asciidoctor.nix";

  outputs = inputs:
    inputs.asciidoctor-nix.mkOutputs inputs {
      packages = {
        inputFile = "pages/index.adoc";
        src = ./src;
      };
    };
}
