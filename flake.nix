{
  description = "Reproducible and Deployable Asciidoctor Template";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";

    git-hooks = {
      inputs = {
        flake-compat.follows = "";
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

        nonDefaultPackages =
          lib.filterAttrs
          (name: _: !lib.hasPrefix "default" name)
          inputs.self.packages.${system};

        pkgs = inputs.nixpkgs.legacyPackages.${system};
      in {
        checks = builtins.foldl' lib.attrsets.unionOfDisjoint {} [
          {
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
          }

          (
            lib.attrsets.concatMapAttrs
            (name: value: {"package-${name}" = value;})
            nonDefaultPackages
          )
        ];

        devShells.default = pkgs.mkShell {
          inherit (inputs.self.checks.${system}.git-hooks) shellHook;

          packages = [
            inputs.self.checks.${system}.git-hooks.enabledPackages
            pkgs.asciidoctor-with-extensions
            pkgs.bundix
          ];
        };

        formatter = pkgs.alejandra;

        packages = let
          asciidoctor = {
            command,
            commandOptions ? {},
            extraOptions ? {},
            inputFile ? "main.adoc",
            name,
            out ? "${builtins.placeholder "out"}/share/doc",
            outputFile,
            src ? ./src,
          }:
            pkgs.stdenvNoCC.mkDerivation (
              lib.attrsets.unionOfDisjoint
              {
                inherit src;

                buildPhase = ''
                  ${command} ${
                    lib.cli.toGNUCommandLineShell
                    {}
                    (
                      lib.attrsets.unionOfDisjoint
                      {
                        attribute = lib.flatten (
                          [
                            "ditaa-format=svg"
                            "mathematical-format=svg"
                            "plantuml-format=svg"
                            "reproducible"
                          ]
                          ++ (
                            lib.optional
                            (commandOptions ? attribute)
                            commandOptions.attribute
                          )
                        );

                        destination-dir = out;
                        out-file = outputFile;
                      }
                      (builtins.removeAttrs commandOptions ["attribute"])
                    )
                  } "${inputFile}"
                '';

                installPhase = ''
                  mkdir --parents "$out" ${lib.escapeShellArg out}
                '';

                name = packageName name;

                nativeBuildInputs = with pkgs;
                  [
                    asciidoctor-with-extensions
                    graphviz
                  ]
                  ++ extraOptions.nativeBuildInputs or [];
              }
              (builtins.removeAttrs extraOptions ["nativeBuildInputs"])
            );

          asciidoctorRequire = {
            require = map (library: "asciidoctor-${library}") [
              "diagram"
              "mathematical"
            ];
          };

          packageName = name: "asciidoctor-nix-${name}";

          presentation = {
            inputFile ? "main.adoc",
            name,
            outputFile,
            revealJsDir,
          }:
            asciidoctor {
              inherit inputFile name outputFile;

              command = "bundle exec asciidoctor-revealjs";

              commandOptions = {
                attribute = "revealjsdir=${revealJsDir}";
              };

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
            paths = lib.attrsets.attrValues nonDefaultPackages;
          };

          defaultExternal = pkgs.buildEnv {
            name = packageName "default-external";

            paths = lib.attrsets.attrValues (
              lib.attrsets.filterAttrs
              (name: _: !lib.hasSuffix "Local" name)
              nonDefaultPackages
            );
          };

          defaultLocal = pkgs.buildEnv {
            name = packageName "default-local";

            paths = lib.attrsets.attrValues (
              lib.attrsets.filterAttrs
              (name: _: !lib.hasSuffix "External" name)
              nonDefaultPackages
            );
          };

          docbook = asciidoctor {
            command = pkgs.asciidoctor.meta.mainProgram;
            commandOptions = asciidoctorRequire;
            name = "docbook";
            outputFile = "main.xml";
          };

          html = asciidoctor {
            command = pkgs.asciidoctor.meta.mainProgram;
            commandOptions = asciidoctorRequire;
            name = "html";
            outputFile = "index.html";
          };

          manpage = let
            sectionNumber = toString 7;
          in
            asciidoctor {
              command = pkgs.asciidoctor.meta.mainProgram;

              commandOptions =
                lib.attrsets.unionOfDisjoint
                asciidoctorRequire
                {backend = "manpage";};

              extraOptions.outputs = ["out" "man"];
              name = "manpage";

              out = "${
                builtins.placeholder "man"
              }/share/man/man${sectionNumber}";

              outputFile = "main.${sectionNumber}";
            };

          pdf = asciidoctor {
            command = "${pkgs.asciidoctor.meta.mainProgram}-pdf";
            commandOptions = asciidoctorRequire;
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
