# Lean parser proofs

Place parser proof modules in this directory. Lake checks every `.lean` file
here and resolves their imports. Modules use the `ParserProofs` prefix, so
`ParserProofs/Example.lean` can be imported as `ParserProofs.Example`.

From the repository root, run:

```bash
cd Sources/LeanParser
lake build
```

Use the Lean version pinned in `lean-toolchain`. Elan selects it automatically
when running Lake from this directory. The build treats warnings as errors,
including proofs that use `sorry`.

Pull requests and the merge queue run the proof build as part of the CI gate.
Nightly verification runs the same proof build.

## Reproduce the type-argument checks from CI

Run these commands from the repository root to generate the 791-case oracle
and exercise the Swift parser with the bundled Lean library:

```bash
bash Scripts/check_lean.sh
```

The script builds the bundled library, checks the proofs, and sets the
oracle path for the Swift parity suite.
