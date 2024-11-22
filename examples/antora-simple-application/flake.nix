{
  description = "Simple Asciidoctor Example Based on Antora's Structure with an Application";

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
                packages = {
                  application-default = let
                    mainProgram = "application";
                  in
                    pkgs.stdenv.mkDerivation {
                      buildPhase = "$CC ${mainProgram}.c -o ${mainProgram}";

                      installPhase = ''
                        mkdir --parent $out/bin
                        cp ${mainProgram} $out/bin
                      '';

                      name = mainProgram;
                      src = src/application;
                    };

                  default = pkgs.buildEnv {
                    name = "default";

                    paths = lib.attrsets.attrValues (
                      lib.filterAttrs
                      (package: _: builtins.match ".*-default" package != null)
                      inputs.self.packages.${system}
                    );
                  };
                };
              }
            )
          )

          (
            inputs.asciidoctor-nix.mkOutputs {
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
