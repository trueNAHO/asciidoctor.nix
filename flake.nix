{
  description = "Reproducible and Deployable Asciidoctor Library";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";

    git-hooks = {
      inputs = {
        flake-compat.follows = "";
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
            runtimeInputs = with pkgs; [bundix gitMinimal nix];

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
              bundix --lock
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
                  set -o errexit
                  set -o nounset
                  set -o pipefail

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

                  nix flake check
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
        mkOutputs = inputs.self.mkOutputs {packages = null;};
        pkgs = inputs.nixpkgs.legacyPackages.${system};
      in {
        inherit (mkOutputs) devShells formatter;

        checks.${system}.git-hooks = mkOutputs.checks.${system}.git-hooks;
        mkLib = lib: lib.extend (final: _: import ./lib final);

        mkOutputs = modifiers:
          inputs.flake-utils.lib.eachDefaultSystem (
            system:
              lib.filterAttrs
              (output: _: modifiers.${output} or true != null)
              (
                lib.fix (
                  self: {
                    checks =
                      lib.attrsets.unionOfDisjoint
                      {
                        git-hooks = inputs.git-hooks.lib.${system}.run (
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
                      }
                      self.packages;

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

                              FONTCONFIG_FILE =
                                lib.optionalString
                                (
                                  builtins.elem
                                  "asciidoctor-mathematical"
                                  commandOptions.require or []
                                )
                                (
                                  pkgs.makeFontsConf {
                                    fontDirectories = [
                                      "${pkgs.lyx}/share/lyx/fonts"
                                    ];
                                  }
                                );

                              SOURCE_DATE_EPOCH =
                                lib.optionalString
                                (lastModified != null)
                                lastModified;

                              buildPhase = let
                                commandLineOptions =
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
                                  );
                              in ''
                                runHook preBuild

                                ${command} \
                                  --attribute root="$src" \
                                  ${commandLineOptions} \
                                  ${lib.escapeShellArg inputFile}

                                runHook postBuild
                              '';

                              installPhase = ''
                                runHook preInstall
                                mkdir --parents "$out" ${lib.escapeShellArg out}
                                runHook postInstall
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
                    in
                      lib.mapAttrs'
                      (
                        name: value: let
                          name' = packageName name;
                        in
                          lib.nameValuePair name' (value name')
                      )
                      (
                        lib.asciidoctor.mergeAttrsMkMerge [
                          {
                            "default" = name:
                              pkgs.buildEnv {
                                inherit name;

                                paths =
                                  lib.attrsets.attrValues
                                  nonDefaultPackages;
                              };

                            "default-external" = name:
                              pkgs.buildEnv {
                                inherit name;

                                paths = lib.attrsets.attrValues (
                                  lib.attrsets.filterAttrs
                                  (name: _: !lib.hasSuffix "-local" name)
                                  nonDefaultPackages
                                );
                              };

                            "default-local" = name:
                              pkgs.buildEnv {
                                inherit name;

                                paths = lib.attrsets.attrValues (
                                  lib.attrsets.filterAttrs
                                  (name: _: !lib.hasSuffix "-external" name)
                                  nonDefaultPackages
                                );
                              };

                            "pdf" = name:
                              asciidoctor (
                                lib.asciidoctor.mergeAttrsMkMerge [
                                  {
                                    inherit name;

                                    command = "${
                                      pkgs.asciidoctor.meta.mainProgram
                                    }-pdf";

                                    commandOptions.require = asciidoctorRequire;
                                    outputFile = "main.pdf";
                                  }

                                  args
                                ]
                              );
                          }

                          (
                            lib.concatMapAttrs
                            (
                              name: value: {
                                "${name}-external" = value false;
                                "${name}-local" = value true;
                              }
                            )
                            (
                              let
                                external = self: local:
                                  lib.optionalAttrs (!local) {
                                    extraOptions = let
                                      out = lib.escapeShellArg self.out;

                                      outputFile = "${out}/${
                                        lib.escapeShellArg
                                        prefix.underscore
                                      }${
                                        lib.escapeShellArg
                                        self.outputFile
                                      }";
                                    in {
                                      nativeBuildInputs = [pkgs.zip];

                                      postBuild = ''
                                        sed \
                                          --in-place \
                                          "s@$src@.@g" \
                                          ${outputFile}
                                      '';

                                      postInstall = ''
                                        directory="$(mktemp --directory)"
                                        mv ${out}/{.,}* "$directory"
                                        rm --recursive "$out"
                                        mkdir --parents "$out" ${out}

                                        # TODO: Replace --update=none with
                                        # --update=none-fail once commit
                                        # de49e993ea8b [1] ("cp: actually
                                        # support --update=none-fail") is
                                        # available.
                                        #
                                        # [1]: https://github.com/coreutils/coreutils/commit/de49e993ea8b6dcdf6cada3c0f44a6371514f952
                                        cp \
                                          --recursive \
                                          --update=none \
                                          "$src/." \
                                          "$directory"

                                        output_file=${outputFile}

                                        cd "$directory"

                                        zip \
                                          --recurse-paths \
                                          "''${output_file%.*}.zip" \
                                          .
                                      '';
                                    };

                                    out = "${
                                      builtins.placeholder "out"
                                    }/share/doc";
                                  };

                                localToString = local:
                                  if local
                                  then "local"
                                  else "external";
                              in {
                                "docbook" = local: name:
                                  asciidoctor (
                                    lib.fix (
                                      self:
                                        lib.asciidoctor.mergeAttrsMkMerge [
                                          {
                                            inherit name;

                                            command =
                                              pkgs.asciidoctor.meta.mainProgram;

                                            commandOptions.require =
                                              asciidoctorRequire;

                                            outputFile = "main_${
                                              localToString local
                                            }.xml";
                                          }

                                          (external self local)
                                          args
                                        ]
                                    )
                                  );

                                "html" = local: name:
                                  asciidoctor (
                                    lib.fix (
                                      self:
                                        lib.asciidoctor.mergeAttrsMkMerge [
                                          {
                                            inherit name;

                                            command =
                                              pkgs.asciidoctor.meta.mainProgram;

                                            commandOptions.require =
                                              asciidoctorRequire;

                                            outputFile = "index_${
                                              localToString local
                                            }.html";
                                          }

                                          (external self local)
                                          args
                                        ]
                                    )
                                  );

                                "presentation" = local: name:
                                  presentation (
                                    lib.fix (
                                      self:
                                        lib.asciidoctor.mergeAttrsMkMerge [
                                          {
                                            inherit name;

                                            outputFile = "presentation_${
                                              localToString local
                                            }.html";

                                            revealJsDir =
                                              if local
                                              then inputs.reveal-js.outPath
                                              else "https://cdn.jsdelivr.net/npm/reveal.js@5.1.0";
                                          }

                                          (external self local)
                                          args
                                        ]
                                    )
                                  );
                              }
                            )
                          )
                        ]
                      );
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
