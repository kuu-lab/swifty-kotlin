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
bash Scripts/build_lean.sh
oracle=$(mktemp)
(cd Sources/LeanParser && lake env lean --run ../../Tests/Formal/TypeArguments.lean) > "$oracle"
KSWIFTK_TYPE_ARGUMENTS_ORACLE="$oracle" bash Scripts/swift_test.sh --no-parallel \
  --filter '^CompilerCoreFrontendTests\.TypeArgumentsLeanParityTests/'
rm -f "$oracle"
```
