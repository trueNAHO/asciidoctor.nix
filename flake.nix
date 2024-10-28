{
  description = "Reproducible Asciidoctor Library";

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
        pkgs = inputs.nixpkgs.legacyPackages.${system};
      in {
        checks = {
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

          packages = [
            inputs.self.checks.${system}.git-hooks.enabledPackages
            pkgs.asciidoctor-with-extensions
            pkgs.bundix
          ];
        };

        formatter = pkgs.alejandra;

        lib = let
          asciidoctor = {
            command,
            commandOptions ? {},
            extraOptions ? {},
            inputFile ? "main.adoc",
            name,
            out ? "${builtins.placeholder "out"}/share/doc",
            outputFile,
            src,
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
                            "root=${src}"
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

          nonDefaultPackages = args:
            lib.filterAttrs
            (name: _: !lib.hasPrefix "default" name)
            (inputs.self.lib.${system}.packages args);

          packageName = name: "asciidoctor-nix-${name}";

          presentation = {revealJsDir, ...} @ args:
            asciidoctor (
              {
                command = "bundle exec asciidoctor-revealjs";
                commandOptions.attribute = "revealjsdir=${revealJsDir}";

                extraOptions.nativeBuildInputs = lib.singleton (
                  pkgs.bundlerEnv
                  {
                    gemdir = ./.;
                    name = packageName "bundler-env";
                  }
                );
              }
              // (builtins.removeAttrs args ["revealJsDir"])
            );
        in {
          packages = args: {
            default = pkgs.buildEnv {
              name = packageName (args.name or "default");

              paths = lib.attrsets.attrValues (
                nonDefaultPackages (builtins.removeAttrs args ["name"])
              );
            };

            defaultExternal = pkgs.buildEnv {
              name = packageName (args.name or "default-external");

              paths = lib.attrsets.attrValues (
                lib.attrsets.filterAttrs
                (name: _: !lib.hasSuffix "Local" name)
                (nonDefaultPackages (builtins.removeAttrs args ["name"]))
              );
            };

            defaultLocal = pkgs.buildEnv {
              name = packageName (args.name or "default-local");

              paths = lib.attrsets.attrValues (
                lib.attrsets.filterAttrs
                (name: _: !lib.hasSuffix "External" name)
                (nonDefaultPackages (builtins.removeAttrs args ["name"]))
              );
            };

            docbook = asciidoctor (
              {
                command = pkgs.asciidoctor.meta.mainProgram;
                commandOptions = asciidoctorRequire;
                name = "docbook";
                outputFile = "main.xml";
              }
              // args
            );

            html = asciidoctor (
              {
                command = pkgs.asciidoctor.meta.mainProgram;
                commandOptions = asciidoctorRequire;
                name = "html";
                outputFile = "index.html";
              }
              // args
            );

            manpage = let
              sectionNumber = toString 7;
            in
              asciidoctor (
                {
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
                }
                // args
              );

            pdf = asciidoctor (
              {
                command = "${pkgs.asciidoctor.meta.mainProgram}-pdf";
                commandOptions = asciidoctorRequire;
                name = "pdf";
                outputFile = "main.pdf";
              }
              // args
            );

            presentationExternal = presentation (
              {
                name = "presentation-external";
                outputFile = "presentation_external.html";
                revealJsDir = "https://cdn.jsdelivr.net/npm/reveal.js@5.0.4";
              }
              // args
            );

            presentationLocal = presentation (
              {
                name = "presentation-local";
                outputFile = "presentation_local.html";
                revealJsDir = inputs.reveal-js.outPath;
              }
              // args
            );
          };
        };
      }
    );
}
