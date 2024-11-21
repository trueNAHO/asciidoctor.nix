{
  description = "Reproducible and Deployable Asciidoctor Library";

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

  outputs = inputs: let
    builtinsReadDirExamples = builtins.readDir examples;
    examples = ./examples;
  in
    inputs.flake-utils.lib.eachDefaultSystem (
      system: let
        inherit (pkgs) lib;
        pkgs = inputs.nixpkgs.legacyPackages.${system};
      in {
        packages = {
          bundix-lock = pkgs.writeShellApplication {
            name = "bundix-lock";
            runtimeInputs = with pkgs; [gitMinimal nix];

            text = let
              src = inputs.self;
            in ''
              check_current_working_directory() {
                git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return

                git ls-files | while read -r file; do
                  diff --brief "${src}/$file" "$file" || return
                done
              }

              if ! check_current_working_directory; then
                printf \
                  'Current directory (%s) does not match expected Nix source tree: %s\n' \
                  "$PWD" \
                  ${src} \
                  >&2

                exit 1
              fi

              rm Gemfile.lock gemset.nix
              nix develop --command bundix --lock
            '';
          };

          check-templates = pkgs.writeShellApplication {
            name = "check-templates";
            runtimeInputs = with pkgs; [nix parallel];

            text = let
              directories = lib.escapeShellArgs (
                lib.attrNames builtinsReadDirExamples
              );
            in ''
              # shellcheck disable=SC2016
              parallel \
                --halt now,fail=1 \
                '
                  flake="$(mktemp --directory)"

                  cleanup() {
                    rm --recursive "$flake"
                  }

                  trap cleanup EXIT

                  cd "$flake"

                  cp --no-preserve=all --recursive "${examples}/{1}/." .

                  sed \
                    --in-place \
                    "s@url = \"github:trueNAHO/asciidoctor.nix\"@url = \"path:${inputs.self}\"@" \
                    flake.nix

                  nix flake show --json |
                    jq --raw-output "
                      .packages |
                      to_entries[0].value |
                      keys[] |
                      select(test(\"default\$\"))
                    " |
                    xargs -I {} nix build .#{}
                ' \
                ::: ${directories}
            '';
          };
        };
      }
    )
    // inputs.flake-utils.lib.eachDefaultSystemPassThrough (
      system: let
        lib = inputs.self.mkLib pkgs.lib;
        pkgs = inputs.nixpkgs.legacyPackages.${system};
      in {
        inherit
          (inputs.self.mkOutputs {packages = null;})
          checks
          devShells
          formatter
          ;

        mkLib = lib: lib.extend (final: _: import ./lib final);

        mkOutputs = modifiers:
          inputs.flake-utils.lib.eachDefaultSystem (
            system:
              lib.filterAttrs
              (output: _: modifiers.${output} or true != null)
              (
                lib.fix (
                  self: {
                    checks.git-hooks = inputs.git-hooks.lib.${system}.run (
                      lib.asciidoctor.mergeAttrsMkMerge [
                        {
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
                        }

                        modifiers.checks or {}
                      ]
                    );

                    devShells.default = pkgs.mkShell (
                      lib.asciidoctor.mergeAttrsMkMerge [
                        {
                          inherit (self.checks.git-hooks) shellHook;

                          packages = [
                            self.checks.git-hooks.enabledPackages
                            pkgs.asciidoctor-with-extensions
                            pkgs.bundix
                          ];
                        }

                        modifiers.devShells or {}
                      ]
                    );

                    formatter = modifiers.formatter or pkgs.alejandra;

                    packages = let
                      args = builtins.removeAttrs rawArgs [
                        "command"
                        "name"
                        "outputFile"
                      ];

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
                          lib.asciidoctor.mergeAttrsMkMerge [
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
                                  lib.optionalString
                                  (lastModified != null)
                                  ''
                                    export SOURCE_DATE_EPOCH="${
                                      toString lastModified
                                    }"
                                  ''
                                }

                                ${command} ${
                                  lib.cli.toGNUCommandLineShell
                                  {}
                                  (
                                    lib.asciidoctor.mergeAttrsMkMerge [
                                      {
                                        attribute = let
                                          format = "svg";
                                        in
                                          [
                                            "attribute-missing=warn"
                                            "bibtex-throw"
                                            "ditaa-format=${format}"
                                            "mathematical-format=${format}"
                                            "plantuml-format=${format}"
                                            "root=${src}"
                                            "source-highlighter=rouge"
                                          ]
                                          ++ (
                                            lib.optional
                                            (lastModified == null)
                                            "reproducible"
                                          );

                                        destination-dir = out;
                                        failure-level = "WARN";

                                        out-file = "${
                                          prefix.underscore
                                        }${outputFile}";
                                      }

                                      commandOptions
                                    ]
                                  )
                                } ${lib.escapeShellArg inputFile}
                              '';

                              installPhase = ''
                                mkdir --parents "$out" ${lib.escapeShellArg out}
                              '';

                              name = packageName name;

                              nativeBuildInputs = with pkgs; [
                                asciidoctor-with-extensions
                                graphviz
                              ];
                            }

                            extraOptions
                          ]
                        );

                      asciidoctorRequire =
                        map
                        (library: "asciidoctor-${library}")
                        (
                          ["diagram" "mathematical"]
                          ++ lib.optional
                          (
                            builtins.any
                            (
                              commandOption:
                                lib.hasPrefix "bibtex-file" commandOption
                            )
                            args.commandOptions.attribute or []
                          )
                          "bibtex"
                        );

                      nonDefaultPackages =
                        lib.filterAttrs
                        (name: _: !lib.hasPrefix "${prefix.hyphen}default" name)
                        self.packages;

                      packageName = name: prefix.hyphen + name;

                      prefix = let
                        prefix = separator:
                          lib.optionalString
                          (rawArgs ? "name")
                          (rawArgs.name + separator);
                      in {
                        hyphen = prefix "-";
                        underscore = prefix "_";
                      };

                      presentation = {revealJsDir, ...} @ args:
                        asciidoctor (
                          lib.asciidoctor.mergeAttrsMkMerge [
                            {
                              command = "bundle exec asciidoctor-revealjs";

                              commandOptions.attribute = [
                                "revealjsdir=${revealJsDir}"
                              ];

                              extraOptions.nativeBuildInputs =
                                lib.singleton
                                (
                                  pkgs.bundlerEnv {
                                    gemdir = ./.;
                                    name = packageName "bundler-env";
                                  }
                                );
                            }

                            (builtins.removeAttrs args ["revealJsDir"])
                          ]
                        );

                      rawArgs = modifiers.packages or {};
                    in {
                      "${prefix.hyphen}default" = pkgs.buildEnv {
                        name = packageName "default";
                        paths = lib.attrsets.attrValues nonDefaultPackages;
                      };

                      "${prefix.hyphen}default-external" = pkgs.buildEnv {
                        name = packageName "default-external";

                        paths = lib.attrsets.attrValues (
                          lib.attrsets.filterAttrs
                          (name: _: !lib.hasSuffix "-local" name)
                          nonDefaultPackages
                        );
                      };

                      "${prefix.hyphen}default-local" = pkgs.buildEnv {
                        name = packageName "default-local";

                        paths = lib.attrsets.attrValues (
                          lib.attrsets.filterAttrs
                          (name: _: !lib.hasSuffix "-external" name)
                          nonDefaultPackages
                        );
                      };

                      "${prefix.hyphen}docbook" = asciidoctor (
                        lib.asciidoctor.mergeAttrsMkMerge [
                          {
                            command = pkgs.asciidoctor.meta.mainProgram;
                            commandOptions.require = asciidoctorRequire;
                            name = "docbook";
                            outputFile = "main.xml";
                          }

                          args
                        ]
                      );

                      "${prefix.hyphen}html" = asciidoctor (
                        lib.asciidoctor.mergeAttrsMkMerge [
                          {
                            command = pkgs.asciidoctor.meta.mainProgram;
                            commandOptions.require = asciidoctorRequire;
                            name = "html";
                            outputFile = "index.html";
                          }

                          args
                        ]
                      );

                      "${prefix.hyphen}pdf" = asciidoctor (
                        lib.asciidoctor.mergeAttrsMkMerge [
                          {
                            command = "${pkgs.asciidoctor.meta.mainProgram}-pdf";
                            commandOptions.require = asciidoctorRequire;
                            name = "pdf";
                            outputFile = "main.pdf";
                          }

                          args
                        ]
                      );

                      "${prefix.hyphen}presentation-external" = presentation (
                        lib.asciidoctor.mergeAttrsMkMerge [
                          {
                            name = "presentation-external";
                            outputFile = "presentation_external.html";
                            revealJsDir = "https://cdn.jsdelivr.net/npm/reveal.js@5.1.0";
                          }

                          args
                        ]
                      );

                      "${prefix.hyphen}presentation-local" = presentation (
                        lib.asciidoctor.mergeAttrsMkMerge [
                          {
                            name = "presentation-local";
                            outputFile = "presentation_local.html";
                            revealJsDir = inputs.reveal-js.outPath;
                          }

                          args
                        ]
                      );
                    };
                  }
                )
              )
          );

        templates =
          lib.attrsets.unionOfDisjoint
          {default = inputs.self.templates.simple;}
          (
            builtins.mapAttrs
            (
              example: _: let
                path = lib.path.append examples example;
              in {
                inherit (import (lib.path.append path "flake.nix")) description;
                inherit path;
              }
            )
            builtinsReadDirExamples
          );
      }
    );
}
