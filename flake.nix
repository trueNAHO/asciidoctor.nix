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
        pkgs = inputs.nixpkgs.legacyPackages.${system};
      in {
        checks.git-hooks = inputs.git-hooks.lib.${system}.run {
          hooks = {
            alejandra = {
              enable = true;
              settings.verbosity = "quiet";
            };

            deadnix.enable = true;
            statix.enable = true;
            typos.enable = true;
            yamllint.enable = true;
          };

          src = ./.;
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
      }
    )
    // inputs.flake-utils.lib.eachDefaultSystemPassThrough (
      system: let
        inherit (pkgs) lib;
        pkgs = inputs.nixpkgs.legacyPackages.${system};
      in {
        mkOutputs = modifier:
          inputs.flake-utils.lib.eachDefaultSystem (
            system:
              lib.filterAttrs (_: value: value != null) (
                let
                  outputs =
                    lib.attrsets.unionOfDisjoint
                    (
                      lib.genAttrs
                      ["checks" "devShells" "formatter"]
                      (output: inputs.self.${output}.${system})
                    )
                    {
                      packages = lib.fix (
                        self: let
                          asciidoctor = {
                            command,
                            commandOptions ? {},
                            extraOptions ? {},
                            inputFile ? "main.adoc",
                            lastModified ? null,
                            name,
                            out ? "${builtins.placeholder "out"}/share/doc",
                            outputFile,
                            src,
                          }:
                            pkgs.stdenvNoCC.mkDerivation (
                              lib.attrsets.unionOfDisjoint
                              (
                                builtins.removeAttrs
                                extraOptions
                                ["nativeBuildInputs"]
                              )
                              {
                                inherit src;

                                buildPhase = ''
                                  ${
                                    lib.optionalString
                                    (
                                      builtins.elem
                                      "asciidoctor-mathematical"
                                      commandOptions.require or []
                                    )
                                    ''
                                      export FONTCONFIG_FILE="${
                                        pkgs.makeFontsConf {
                                          fontDirectories = [
                                            "${pkgs.lyx}/share/lyx/fonts"
                                          ];
                                        }
                                      }"
                                    ''
                                  }

                                  ${
                                    lib.optionalString (lastModified != null) ''
                                      export SOURCE_DATE_EPOCH="${
                                        toString lastModified
                                      }"
                                    ''
                                  }

                                  ${command} ${
                                    lib.cli.toGNUCommandLineShell
                                    {}
                                    (
                                      lib.attrsets.unionOfDisjoint
                                      (
                                        builtins.removeAttrs
                                        commandOptions
                                        ["attribute"]
                                      )
                                      {
                                        attribute = let
                                          format = "svg";
                                        in
                                          [
                                            "attribute-missing=error"
                                            "ditaa-format=${format}"
                                            "mathematical-format=${format}"
                                            "plantuml-format=${format}"
                                            "root=${src}"
                                          ]
                                          ++ commandOptions.attribute or []
                                          ++ (
                                            lib.optional
                                            (lastModified == null)
                                            "reproducible"
                                          );

                                        destination-dir = out;
                                        out-file = outputFile;
                                      }
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
                            (self (builtins.removeAttrs args ["name"]));

                          packageName = name: "asciidoctor-nix-${name}";

                          presentation = {revealJsDir, ...} @ args:
                            asciidoctor (
                              {
                                command = "bundle exec asciidoctor-revealjs";

                                commandOptions.attribute = [
                                  "revealjsdir=${revealJsDir}"
                                ];

                                extraOptions.nativeBuildInputs = lib.singleton (
                                  pkgs.bundlerEnv {
                                    gemdir = ./.;
                                    name = packageName "bundler-env";
                                  }
                                );
                              }
                              // (builtins.removeAttrs args ["revealJsDir"])
                            );
                        in
                          args: {
                            default = pkgs.buildEnv {
                              name = packageName (args.name or "default");

                              paths = lib.attrsets.attrValues (
                                nonDefaultPackages args
                              );
                            };

                            defaultExternal = pkgs.buildEnv {
                              name = packageName (
                                args.name or "default-external"
                              );

                              paths = lib.attrsets.attrValues (
                                lib.attrsets.filterAttrs
                                (name: _: !lib.hasSuffix "Local" name)
                                (nonDefaultPackages args)
                              );
                            };

                            defaultLocal = pkgs.buildEnv {
                              name = packageName (args.name or "default-local");

                              paths = lib.attrsets.attrValues (
                                lib.attrsets.filterAttrs
                                (name: _: !lib.hasSuffix "External" name)
                                (nonDefaultPackages args)
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
                                revealJsDir = "https://cdn.jsdelivr.net/npm/reveal.js@5.1.0";
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
                          }
                      );
                    };
                in
                  lib.mapAttrs
                  (
                    let
                      modifiedOutputs = modifier outputs;
                    in
                      name: value: modifiedOutputs.${name} or value
                  )
                  outputs
              )
          );

        templates =
          lib.attrsets.unionOfDisjoint
          {default = inputs.self.templates.simple;}
          (
            let
              examples = ./examples;
            in
              builtins.mapAttrs
              (
                example: _: let
                  path = lib.path.append examples example;
                in {
                  inherit
                    (import (lib.path.append path "flake.nix"))
                    description
                    ;

                  inherit path;
                }
              )
              (builtins.readDir examples)
          );
      }
    );
}
