# serialization exception contracts

KUU-1739 supplies `SerializationException` and `MissingFieldException` from
serialization 1.10.0, immutable commit
`370c4e3780066b82f746cf38e4733cbe62c94f74`.
`serialization-exceptions-provenance.json` records the source Git blob, upstream
SHA-256 and local SHA-256. Only documentation-only imports and the resulting redundant blank line
are removed; the declarations, implementations, annotations and copyright remain.
The pinned upstream Apache license is in `Scripts/serialization_reference`.

`SerializationException` remains an open `IllegalArgumentException` subclass with
four constructors. Its message and cause follow the underlying exception contract.
`MissingFieldException` retains its experimental marker, two current public
constructors, exact single/plural messages, `missingFields` and nullable
`serialName`. The source also retains the ERROR-deprecated compatibility constructor,
HIDDEN internal constructor and internal helper declarations.

The list constructor retains the original list; it does not copy it or reject an
empty list. Those edge cases are checked against the actual upstream JVM library,
rather than inferred from the documentation saying the list is non-empty.

`Scripts/reference_cases/serialization_exceptions.kt` is the executable Kotlin
example. Its expected output comes from Kotlin JVM 2.3.10 with the pinned
`kotlinx-serialization-core-jvm:1.10.0` artifact, and includes cause identity,
subclass catch behavior, list aliasing and empty-list messages. The cause-only
constructor checks its message against `cause.toString()` so platform-specific
exception class names do not change the comparison.

```bash
kotlinc Scripts/reference_cases/serialization_exceptions.kt \
  -classpath /path/to/kotlinx-serialization-core-jvm-1.10.0.jar \
  -d /tmp/serialization-exceptions.jar
kotlin -classpath /tmp/serialization-exceptions.jar:/path/to/kotlinx-serialization-core-jvm-1.10.0.jar \
  Serialization_exceptionsKt > /tmp/serialization-exceptions.stdout
diff -u Scripts/reference_cases/serialization_exceptions.expected /tmp/serialization-exceptions.stdout
```

The focused `SerializationExceptionsTests` exercises bundled source, prebuilt
stdlib and a separately compiled `.kklib` producer/consumer at O0/O2. Frontend
checks cover experimental opt-in, the deprecated constructor and private/HIDDEN
constructor availability in source and prebuilt modes.

The upstream constructor annotations exposed an AST bug: delegation parsing used
the first parenthesis in the declaration, which belonged to `@Deprecated(...)`,
and lost the later `this(...)`. Parameter and delegation scans now share the
constructor-header scan and skip complete annotations, including comparisons and
an annotation aliased as `constructor`. The minimal
`annotated_constructor_delegation.kt` regression runs at O0/O2.

Constructor calls also inherit opt-in requirements from their owning class,
deduplicating markers present on both class and constructor. The small
`serialization_exceptions_no_optin.kt` fixture checks the upstream experimental
warning without an explicit return-type annotation.

Automatic serializer generation and its missing-field throws, formats, the full
upstream suite and Native/macOS distribution remain with parent KUU-1724.
