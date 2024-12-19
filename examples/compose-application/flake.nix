{
  description = "Composable Asciidoctor Example with an Application";

  inputs = {
    asciidoctor-nix.url = "github:trueNAHO/asciidoctor.nix";
    flake-utils.follows = "asciidoctor-nix/flake-utils";
    nixpkgs.follows = "asciidoctor-nix/nixpkgs";
  };

  outputs = inputs:
    inputs.flake-utils.lib.eachDefaultSystemPassThrough (
      system: let
        lib = inputs.asciidoctor-nix.mkLib pkgs.lib;

        mkOutputs = name:
          inputs.asciidoctor-nix.mkOutputs {
            checks.hooks = {
              clang-format.enable = true;
              clang-tidy.enable = true;
            };

            packages = {
              inherit (inputs.self) lastModified;
              inherit name;

              src = ./src + "/${name}";
            };
          };

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
                        buildPhase = "$CC ${mainProgram}.c -o ${mainProgram}";

                        installPhase = ''
                          mkdir --parent $out/bin
                          cp ${mainProgram} $out/bin
                        '';

                        name = mainProgram;
                        src = src/application;
                      };

                    application-default-external = self.application-default;
                    application-default-local = self.application-default;

                    default = pkgs.buildEnv {
                      name = "default";

                      paths = lib.attrsets.attrValues (
                        lib.filterAttrs
                        (name: _: lib.hasSuffix "-default" name)
                        inputs.self.packages.${system}
                      );
                    };

                    default-external = pkgs.buildEnv {
                      name = "default-external";

                      paths = lib.attrsets.attrValues (
                        lib.filterAttrs
                        (name: _: lib.hasSuffix "-default-external" name)
                        inputs.self.packages.${system}
                      );
                    };

                    default-local = pkgs.buildEnv {
                      name = "default-local";

                      paths = lib.attrsets.attrValues (
                        lib.filterAttrs
                        (name: _: lib.hasSuffix "-default-local" name)
                        inputs.self.packages.${system}
                      );
                    };
                  }
                );
              }
            )
          )

          (mkOutputs "presentation")
          (mkOutputs "report")
        ]
    );
}
