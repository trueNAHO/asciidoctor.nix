{
  description = "Asciidoctor example with application and report";

  inputs = {
    asciidoctor-nix.url = "github:trueNAHO/asciidoctor.nix";
    flake-utils.follows = "asciidoctor-nix/flake-utils";
    nixpkgs.follows = "asciidoctor-nix/nixpkgs";
  };

  outputs = inputs:
    inputs.flake-utils.lib.eachDefaultSystemPassThrough (
      system: let
        lib = inputs.asciidoctor-nix.mkLib pkgs.lib;
        pkgs = inputs.nixpkgs.legacyPackages.${system};
      in
        lib.asciidoctor.mergeAttrsMkMerge [
          (
            inputs.flake-utils.lib.eachDefaultSystem (
              _: {
                packages = lib.fix (
                  self: {
                    application-default = let
                      mainProgram = "application";
                    in
                      pkgs.stdenv.mkDerivation {
                        buildPhase = "$CC main.c -o ${mainProgram}";

                        installPhase = ''
                          mkdir --parent $out/bin
                          cp ${mainProgram} $out/bin
                        '';

                        name = mainProgram;
                        src = src/application/src;
                      };

                    application-default-external = self.application-default;
                    application-default-local = self.application-default;
                  }
                );
              }
            )
          )

          (
            inputs.asciidoctor-nix.mkOutputs inputs {
              checks.hooks = {
                clang-format.enable = true;
                clang-tidy.enable = true;
              };

              packages = {
                inherit (inputs.self) lastModified;

                name = "report";
                src = src/report;
              };
            }
          )
        ]
    );
}
