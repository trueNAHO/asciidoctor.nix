{
  description = ''
    Reproducible and Deployable Asciidoctor Template:
    https://github.com/trueNAHO/asciidoctor.nix
  '';

  inputs = {
    flakeUtils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    preCommitHooks = {
      inputs = {
        flake-utils.follows = "flakeUtils";
        nixpkgs-stable.follows = "preCommitHooks/nixpkgs";
        nixpkgs.follows = "nixpkgs";
      };

      url = "github:cachix/pre-commit-hooks.nix";
    };

    revealJs = {
      flake = false;
      url = "github:hakimel/reveal.js";
    };
  };

  outputs = {
    self,
    flakeUtils,
    nixpkgs,
    preCommitHooks,
    revealJs,
    ...
  }:
    flakeUtils.lib.eachDefaultSystem (
      system: let
        packagesExcludingDefaults =
          pkgs.lib.attrsets.filterAttrs
          (
            k: _:
              k != "default" && k != "defaultExternal" && k != "defaultLocal"
          )
          self.packages.${system};

        pkgs = nixpkgs.legacyPackages.${system};
      in {
        checks =
          (
            pkgs.lib.attrsets.concatMapAttrs
            (k: v: {"${k}Package" = v;})
            packagesExcludingDefaults
          )
          // {
            preCommitHooks = preCommitHooks.lib.${system}.run {
              hooks = {
                alejandra.enable = true;
                convco.enable = true;
                typos.enable = true;
                yamllint.enable = true;
              };

              settings.alejandra.verbosity = "quiet";
              src = ./.;
            };
          };

        devShells.default = pkgs.mkShell {
          inherit (self.checks.${system}.preCommitHooks) shellHook;
          packages = with pkgs; [asciidoctor-with-extensions bundix];
        };

        packages = let
          asciidoctor = {
            command,
            extraOptions ? {},
            inputFile ? "main.adoc",
            name,
            out ? "$out/share/doc",
            outputFile,
            src ? ./src,
          }: let
            outputPath = ".${out}/${outputFile}";
          in
            pkgs.stdenv.mkDerivation ({
                inherit src;

                buildPhase = ''
                  ${command} --out-file "${outputPath}" "${inputFile}"
                '';

                installPhase = ''
                  mkdir --parent "$out" "${out}"
                  mv "${outputPath}" "${out}"
                '';

                name = packageName name;
                nativeBuildInputs = [pkgs.asciidoctor-with-extensions];
              }
              // extraOptions);

          packageName = name: "truenaho-asciidoctor-nix-${name}";

          presentation = {
            attribute,
            name,
            outputFile,
          }:
            asciidoctor {
              inherit name outputFile;

              command = "bundle exec asciidoctor-revealjs --attribute revealjsdir=${attribute}";

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
            paths = pkgs.lib.attrsets.attrValues packagesExcludingDefaults;
          };

          defaultExternal = pkgs.buildEnv {
            name = packageName "default-external";
            paths = pkgs.lib.attrsets.attrValues (
              pkgs.lib.attrsets.filterAttrs
              (k: _: k != "presentationLocal")
              packagesExcludingDefaults
            );
          };

          defaultLocal = pkgs.buildEnv {
            name = packageName "default-local";
            paths = pkgs.lib.attrsets.attrValues (
              pkgs.lib.attrsets.filterAttrs
              (k: _: k != "presentationExternal")
              packagesExcludingDefaults
            );
          };

          docbook = asciidoctor {
            command = pkgs.asciidoctor.meta.mainProgram;
            name = "docbook";
            outputFile = "main.xml";
          };

          html = asciidoctor {
            command = pkgs.asciidoctor.meta.mainProgram;
            name = "html";
            outputFile = "index.html";
          };

          manpage = let
            sectionNumber = toString 7;
          in
            asciidoctor {
              command = "${pkgs.asciidoctor.meta.mainProgram} --backend manpage";
              extraOptions.outputs = ["out" "man"];
              name = "manpage";
              out = "$man/share/man/man${sectionNumber}";
              outputFile = "main.${sectionNumber}";
            };

          pdf = asciidoctor {
            command = "${pkgs.asciidoctor.meta.mainProgram}-pdf";
            name = "pdf";
            outputFile = "main.pdf";
          };

          presentationExternal = presentation {
            attribute = "https://cdn.jsdelivr.net/npm/reveal.js@5.0.4";
            name = "presentation-external";
            outputFile = "presentation_external.html";
          };

          presentationLocal = presentation {
            attribute = revealJs.outPath;
            name = "presentation-local";
            outputFile = "presentation_local.html";
          };
        };
      }
    );
}
