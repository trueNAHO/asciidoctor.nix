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
  };

  outputs = {
    self,
    flakeUtils,
    nixpkgs,
    preCommitHooks,
    ...
  }:
    flakeUtils.lib.eachDefaultSystem (
      system: let
        packagesExcludingDefault =
          pkgs.lib.attrsets.filterAttrs
          (k: _: k != "default")
          self.packages.${system};

        pkgs = nixpkgs.legacyPackages.${system};
      in {
        checks =
          (
            pkgs.lib.attrsets.concatMapAttrs
            (k: v: {"${k}Package" = v;})
            packagesExcludingDefault
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
        in {
          default = pkgs.buildEnv {
            name = packageName "default";
            paths = pkgs.lib.attrsets.attrValues packagesExcludingDefault;
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
        };
      }
    );
}
