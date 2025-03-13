{
  description = "Asciidoctor example with report";
  inputs.asciidoctor-nix.url = "github:trueNAHO/asciidoctor.nix";

  outputs = inputs:
    inputs.asciidoctor-nix.mkOutputs {
      packages = {
        inherit (inputs.self) lastModified;
        src = ./src;
      };
    };
}
