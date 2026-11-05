{
  description = "Skills for working on wire-server and Haskell projects";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Provides `claude` for the ci dev shell.
    llm-agents.url = "git+https://github.com/numtide/llm-agents.nix";
    # Pinned skill-creator, vendored to .claude/skills/skill-creator (see `sync-skill-creator`).
    anthropic-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      llm-agents,
      anthropic-skills,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        python = pkgs.python3.withPackages (p: [ p.pyyaml ]);
        skillCreator = "${anthropic-skills}/skills/skill-creator";
        skill = "skills/wire-haskell-developer";

        script =
          name: runtimeInputs:
          pkgs.writeShellApplication {
            inherit name runtimeInputs;
            text = builtins.readFile ./scripts/${name}.sh;
            # Scripts carry their own shebang/options.
            bashOptions = [ ];
          };

        checkCoverage = script "check-coverage" [ pkgs.jq pkgs.gnused pkgs.coreutils ];
        genReference = script "gen-reference" [ pkgs.jq pkgs.gnused ];
        runEvals = script "run-evals" [
          pkgs.jq
          pkgs.coreutils
          pkgs.gnugrep
          python
        ];
        cloneRepos = script "clone-repos" [ pkgs.git ];

        syncSkillCreator = pkgs.writeShellApplication {
          name = "sync-skill-creator";
          text = ''
            rm -rf .claude/skills/skill-creator
            mkdir -p .claude/skills
            cp -r --no-preserve=mode ${skillCreator} .claude/skills/skill-creator
          '';
        };
        writeReference = pkgs.writeShellApplication {
          name = "gen-reference-write";
          runtimeInputs = [ genReference ];
          text = "gen-reference > REFERENCE.md";
        };

        app = drv: description: {
          type = "app";
          program = pkgs.lib.getExe drv;
          meta.description = description;
        };

        # Hermetic, read-only check on the repo source.
        check =
          name: inputs: cmd:
          pkgs.runCommand "check-${name}" { nativeBuildInputs = inputs; } ''
            cd ${self}
            ${cmd}
            touch $out
          '';
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            python
            pkgs.jq
            pkgs.git
          ];
        };

        # CI only: locally the agent comes from the outer environment.
        devShells.ci = pkgs.mkShell {
          inputsFrom = [ self.devShells.${system}.default ];
          packages = [ llm-agents.packages.${system}.claude-code ];
        };

        apps = {
          evals = app runEvals "Run LLM evals (needs claude + auth)";
          gen-reference = app writeReference "Regenerate REFERENCE.md";
          sync-skill-creator = app syncSkillCreator "Vendor pinned skill-creator into .claude/skills";
          clone-repos = app cloneRepos "Clone wire-server and ldap-scim-bridge into ./tmp";
        };

        checks = {
          skill-creator-pinned = check "skill-creator-pinned" [ ] ''
            diff -r ${skillCreator} .claude/skills/skill-creator
          '';
          skill-valid = check "skill-valid" [ python ] ''
            python ${skillCreator}/scripts/quick_validate.py ${skill}
          '';
          symlinks = check "symlinks" [ ] ''
            [ "$(readlink CLAUDE.md)" = AGENTS.md ]
            [ "$(readlink -f .claude/skills/wire-haskell-developer)" = "$PWD/${skill}" ]
          '';
          rule-coverage = check "rule-coverage" [ checkCoverage ] "check-coverage";
          reference-fresh = check "reference-fresh" [ genReference ] ''
            gen-reference | diff - REFERENCE.md
          '';
        };
      }
    );
}
