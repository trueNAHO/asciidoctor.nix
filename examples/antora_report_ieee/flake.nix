{
  description = "IEEE Antora example with report";
  inputs.asciidoctor-nix.url = "github:trueNAHO/asciidoctor.nix";

  outputs = inputs:
    inputs.asciidoctor-nix.mkOutputs inputs {
      packages = {
        commandOptions.attribute = [
          "bibtex-file=attachments/bibtex.bib"
          "bibtex-order=alphabetical"

          "pdf-theme=${
            builtins.toFile "default-theme.yml" (
              builtins.toJSON {
                abstract = {
                  first-line.font-style = null;
                  font-size = "$base-font-size";
                  line-height = "$base-line-height";
                };

                # Fit 80 characters on one line.
                code = let
                  fontSize = 5.813;
                in {
                  font-size = fontSize;
                  padding = fontSize;
                };

                extends = "default";
                page.columns = 2;
              }
            )
          }"
        ];

        inputFile = "pages/index.adoc";
        src = ./src;
      };
    };
}
