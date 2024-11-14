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

                  nix build
                ' \
                ::: ${directories}
            '';
          };
        };
      }
    )
    // inputs.flake-utils.lib.eachDefaultSystemPassThrough (
      system: let
        lib = pkgs.lib.extend (final: _: import ./lib final);
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
                            out ? builtins.placeholder "out",
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
                                            out-file = outputFile;
                                          }

                                          commandOptions
                                        ]
                                      )
                                    } ${lib.escapeShellArg inputFile}
                                  '';

                                  installPhase = ''
                                    mkdir --parents "$out" ${
                                      lib.escapeShellArg out
                                    }
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
                            ["bibtex" "diagram" "mathematical"];

                          packageName = name: "asciidoctor-nix-${name}";

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
                        in
                          args: let
                            nonDefaultPackages =
                              lib.filterAttrs
                              (name: _: !lib.hasPrefix "default" name)
                              (self (builtins.removeAttrs args ["name"]));
                          in {
                            default = pkgs.buildEnv {
                              name = packageName (args.name or "default");

                              paths =
                                lib.attrsets.attrValues nonDefaultPackages;
                            };

                            defaultExternal = pkgs.buildEnv {
                              name = packageName (
                                args.name or "default-external"
                              );

                              paths = lib.attrsets.attrValues (
                                lib.attrsets.filterAttrs
                                (name: _: !lib.hasSuffix "Local" name)
                                nonDefaultPackages
                              );
                            };

                            defaultLocal = pkgs.buildEnv {
                              name = packageName (args.name or "default-local");

                              paths = lib.attrsets.attrValues (
                                lib.attrsets.filterAttrs
                                (name: _: !lib.hasSuffix "External" name)
                                nonDefaultPackages
                              );
                            };

                            docbook = asciidoctor (
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

                            html = asciidoctor (
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

                            pdf = asciidoctor (
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

                            presentationExternal = presentation (
                              lib.asciidoctor.mergeAttrsMkMerge [
                                {
                                  name = "presentation-external";
                                  outputFile = "presentation_external.html";
                                  revealJsDir = "https://cdn.jsdelivr.net/npm/reveal.js@5.1.0";
                                }

                                args
                              ]
                            );

                            presentationLocal = presentation (
                              lib.asciidoctor.mergeAttrsMkMerge [
                                {
                                  name = "presentation-local";
                                  outputFile = "presentation_local.html";
                                  revealJsDir = inputs.reveal-js.outPath;
                                }

                                args
                              ]
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
