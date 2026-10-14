# java.lang.Character native facade

KUU-2039 adds the source-backed `java.lang.Character` object for
`charCount(Int): Int`, `isSpaceChar(Int): Boolean`, `getType(Int): Int`, and
the `Byte` constants `NON_SPACING_MARK = 6`, `ENCLOSING_MARK = 7`, `FORMAT = 16`.
Default `java.lang` lookup, explicit imports, aliases, and qualified calls use
the same bundled declaration in source and `.kklib` consumers.

The contracts follow [Java SE 17 Character](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/lang/Character.html):

- `charCount` returns 2 for every input >= 0x10000 and 1 otherwise, including
  invalid code points. It does not throw or validate the input.
- `isSpaceChar` accepts only Unicode categories Zs, Zl, Zp (12–14), including
  non-breaking spaces. Tabs and line feeds are not space characters.
- `getType` supports supplementary code points without truncating to a UTF-16
  code unit. Surrogates return 19; invalid code points return 0. The shared
  `__kk_char_unicode_category` bridge returns `CharCategory` ordinals 0–29;
  Java leaves 17 unused, so ordinals >= 17 map to ordinal + 1. Kotlin `Char`
  classification and category ordinals are unchanged.

Java SE 17 specifies Unicode 13.0. Native classification uses the Swift runtime's
Unicode tables, as existing Kotlin `Char` APIs do; it does not pin a Unicode 13.0
database. Newly assigned or reclassified characters can therefore differ by
Swift toolchain/runtime versus JVM release. Regression representatives use
stable categories; this is not a claim of Unicode-version-wide JVM parity.

The public xenocom sources at commit
[`745f41619f2e230b2705fa50835bb85ea6532963`](https://github.com/xenomachina/xenocom/tree/745f41619f2e230b2705fa50835bb85ea6532963)
use these operations in `Text.kt` and `TextTerm.kt`. Remaining consumer blockers
are independent: `String.codePointAt` (KUU-2038),
`StringBuilder.appendCodePoint` (KUU-2040), and `Array.maxBy` (KUU-2045).
This facade does not claim support for Character boxing/constructors or the
other Java Character overloads and methods.

## Focused validation

Verified on 2026-10-14 against base commit
`bc8819f1532c612ca7d528ff0932d3b5c5bcf095` plus this patch:

- `swift build` succeeded.
- `JavaCharacterTests` passed default, explicit, and alias import signature
  checks, including `Int`/`Boolean` method results and `Byte` constants.
- `testJavaCharacterUnicodeAcrossStdlibSurfaces` passed all four executable
  paths: source/fresh `.kklib` × O0/O2. The 78 output lines cover every general
  category, supplementary characters, surrogates, invalid inputs, separator
  controls, xenocom's category comparisons, and the existing char/builder controls.
- The single `java_character_unicode.kt` diff case passed O0 and O2 against
  Kotlin/JVM 2.3.10 on JDK 21. The fixture pins the JDK API surface to 17;
  the manually obtained API-17 reference output matches the backend expectations.
- The issue's exact three-function minimum with an empty `main` compiled to
  objects successfully on source/fresh `.kklib` × O0/O2 (compile-only).
- Unmodified `Text.kt` and `TextTerm.kt` from the pinned OSS commit compiled
  successfully with Kotlin/JVM 2.3.10 and JDK API 17. Native library compilation
  still exited 1 on all four paths, with byte-identical diagnostics for
  `codePointAt`, `appendCodePoint`, and `maxBy` (including its `size()` cascade).
  No Character or `getType().toByte()` cascade diagnostic remained. The original
  consumer was not executed.

The full Swift, Golden, and diff suites were not run. These checks establish
the facade's focused contracts, not complete xenocom execution or parity
across all Unicode table versions.

### Post-rebase PR gates

The implementation was rebased onto `01544852e570d6bb1766e44b4e9fb47af88121f2`.
Commit `fadcac969ee50ed71f6d913b08a74c67d0f57620` passed `swift build --jobs 4`,
the three import/signature cases, and the backend source/fresh-artifact × O0/O2
executable matrix. A regenerated CLI stdlib artifact with manifest hash
`040ee990e75b9569` also passed the single diff case at O0 and O2, with no skips,
using Kotlin/JVM 2.3.10 and the fixture's JDK API 17 directive.
The minimum and original-closure measurements above remain initial-base
measurements; they were not repeated after the rebase. Full suites remain unrun.
