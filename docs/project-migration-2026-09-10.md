# Project migration

- Source: `claude-dotfiles/output/gyaru-secretary`
- Destination: sibling project `gyaru-secretary` under `/Volumes/SanD/Mac_m1_mini_archive/Git_full_no_xattrs`.
- Moved all 40 files, including generated media and existing build outputs. SHA-256 values and relative paths matched before and after the move.
- No references from other dotfiles repository files were found in a repository-wide search excluding the prototype itself.
- Initialized an independent Git repository and preserved the pre-redesign prototype as commit `f3c0b7d`.
- Build scripts resolve paths relative to their own project directory. Rebuilt the application with its new ProjectRoot.
- Stopped the prior prototype's matching Python bridge process and started the bridge from the new project directory. The runtime-file location is unchanged to preserve local app connectivity.
- Kept generated phone/playful clips and audio samples. Their old application integration is recoverable from the initial commit.
- No remote repository was created or published. No unrelated dotfiles were changed.
