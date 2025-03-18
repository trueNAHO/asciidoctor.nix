{
  description = "Antora example with themed presentation";
  inputs.asciidoctor-nix.url = "github:trueNAHO/asciidoctor.nix";

  outputs = inputs:
    inputs.asciidoctor-nix.mkOutputs inputs {
      packages = rec {
        commandOptions.attribute = ["customcss=${src}/theme.css"];
        inputFile = "pages/index.adoc";
        src = ./src;
      };
    };
}
