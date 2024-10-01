{
  description = ''
    Reproducible and Deployable Asciidoctor Template:
    https://github.com/trueNAHO/asciidoctor.nix
  '';

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";

    git-hooks = {
      inputs = {
        nixpkgs-stable.follows = "git-hooks/nixpkgs";
        nixpkgs.follows = "nixpkgs";
      };

      url = "github:cachix/git-hooks.nix";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    reveal-js = {
      flake = false;
      url = "github:hakimel/reveal.js";
    };
  };

  outputs = inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system: let
        lib = pkgs.lib;

        packagesExcludingDefaults = builtins.removeAttrs
        inputs.self.packages.${system}
        ["default" "defaultExternal" "defaultLocal"];

        pkgs = inputs.nixpkgs.legacyPackages.${system};
      in {
        checks =
          (
            lib.attrsets.concatMapAttrs
            (name: value: {"${name}Package" = value;})
            packagesExcludingDefaults
          )
          // {
            git-hooks = inputs.git-hooks.lib.${system}.run {
              hooks = {
                alejandra = {
                  enable = true;
                  settings.verbosity = "quiet";
                };

                typos.enable = true;
                yamllint.enable = true;
              };

              src = ./.;
            };
          };

        devShells.default = pkgs.mkShell {
          inherit (inputs.self.checks.${system}.git-hooks) shellHook;

          packages = with pkgs;
            [asciidoctor-with-extensions bundix]
            ++ [inputs.self.checks.${system}.git-hooks.enabledPackages];
        };

        packages = let
          asciidoctor = {
            command,
            extraOptions ? {},
            inputFile ? "main.adoc",
            name,
            out ? "${builtins.placeholder "out"}/share/doc",
            outputFile,
            src ? ./src,
          }:
            pkgs.stdenvNoCC.mkDerivation ({
                inherit src;

                buildPhase = ''
                  ${lib.removeSuffix "\n" command} \
                    --attribute ditaa-format=svg \
                    --attribute mathematical-format=svg \
                    --attribute plantuml-format=svg \
                    --destination-dir "${out}" \
                    --out-file "${outputFile}" \
                    "${inputFile}"
                '';

                installPhase = ''mkdir --parents "$out" "${out}"'';
                name = packageName name;

                nativeBuildInputs = with pkgs; [
                  asciidoctor-with-extensions
                  graphviz
                ];
              }
              // extraOptions);

          asciidoctorRequire =
            lib.concatMapStringsSep
            " "
            (library: "--require asciidoctor-${library}")
            ["diagram" "mathematical"];

          packageName = name: "truenaho-asciidoctor-nix-${name}";

          presentation = {
            name,
            outputFile,
            revealJsDir,
          }:
            asciidoctor {
              inherit name outputFile;

              command = ''
                bundle \
                  exec \
                  asciidoctor-revealjs \
                  --attribute revealjsdir=${revealJsDir}
              '';

              extraOptions.nativeBuildInputs = [
                (
                  pkgs.bundlerEnv
                  {
                    gemdir = ./.;
                    name = packageName "bundler-env";
                  }
                )
              ];
            };
        in {
          default = pkgs.buildEnv {
            name = packageName "default";
            paths = lib.attrsets.attrValues packagesExcludingDefaults;
          };

          defaultExternal = pkgs.buildEnv {
            name = packageName "default-external";

            paths = lib.attrsets.attrValues (
              lib.attrsets.filterAttrs
              (name: _: name != "presentationLocal")
              packagesExcludingDefaults
            );
          };

          defaultLocal = pkgs.buildEnv {
            name = packageName "default-local";

            paths = lib.attrsets.attrValues (
              lib.attrsets.filterAttrs
              (name: _: name != "presentationExternal")
              packagesExcludingDefaults
            );
          };

          docbook = asciidoctor {
            command = ''
              ${pkgs.asciidoctor.meta.mainProgram} ${asciidoctorRequire}
            '';

            name = "docbook";
            outputFile = "main.xml";
          };

          html = asciidoctor {
            command = ''
              ${pkgs.asciidoctor.meta.mainProgram} ${asciidoctorRequire}
            '';

            name = "html";
            outputFile = "index.html";
          };

          manpage = let
            sectionNumber = toString 7;
          in
            asciidoctor {
              command = ''
                ${pkgs.asciidoctor.meta.mainProgram} \
                  --backend manpage \
                  ${asciidoctorRequire}
              '';

              extraOptions.outputs = ["out" "man"];
              name = "manpage";

              out = "${
                builtins.placeholder "man"
              }/share/man/man${sectionNumber}";

              outputFile = "main.${sectionNumber}";
            };

          pdf = asciidoctor {
            command = ''
              ${pkgs.asciidoctor.meta.mainProgram}-pdf ${asciidoctorRequire}
            '';

            name = "pdf";
            outputFile = "main.pdf";
          };

          presentationExternal = presentation {
            name = "presentation-external";
            outputFile = "presentation_external.html";
            revealJsDir = "https://cdn.jsdelivr.net/npm/reveal.js@5.0.4";
          };

          presentationLocal = presentation {
            name = "presentation-local";
            outputFile = "presentation_local.html";
            revealJsDir = inputs.reveal-js.outPath;
          };
        };
      }
    );
}
