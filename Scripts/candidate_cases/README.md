# Candidate-only Kotlin cases

These cases use `kswiftc` directly and compare program stdout with a checked-in
`.expected` file. They are kept outside `diff_cases` because they do not use a
JVM `kotlinc` reference.

Run a case from the repository root:

```bash
bash Scripts/run_candidate_only.sh \
  Scripts/candidate_cases/logging_basic.kt \
  Scripts/candidate_cases/support/slf4j_minimal.kt
```

Additional Kotlin sources are compiled into the same candidate module. Test
support sources may model the small external API surface a case needs; they do
not establish compatibility with the original external library. The logging
case uses SLF4J's logger-name overload because its original `Class.java`
argument is JVM-specific and unavailable to KSwiftK's native target.
