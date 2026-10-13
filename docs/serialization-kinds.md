# serialization descriptor kinds

KUU-1738 adds the source API for `SerialKind`, `PrimitiveKind`, `StructureKind`,
and `PolymorphicKind` from serialization 1.10.0. Their 17 singleton values are:

| Family | Kinds |
| --- | --- |
| SerialKind | ENUM, CONTEXTUAL |
| PrimitiveKind | BOOLEAN, BYTE, CHAR, SHORT, INT, LONG, FLOAT, DOUBLE, STRING |
| StructureKind | CLASS, LIST, MAP, OBJECT |
| PolymorphicKind | SEALED, OPEN |

The source retains the sealed hierarchy, singleton identity, kind-name `toString`,
and stable `hashCode` derived from that string. The three upstream API-level
annotations keep their targets, opt-in levels, documentation and message;
PolymorphicKind remains experimental. This supplies descriptor-kind behavior,
not descriptors, encoders/decoders, serializers or any wire format.

`serialization-kinds-provenance.json` records the two upstream paths, Git blobs,
SHA-256 and local source hashes at immutable commit
`370c4e3780066b82f746cf38e4733cbe62c94f74`. Adaptations remove unused imports used
only by documentation links and trim a final empty line. Copyright headers remain;
the upstream Apache license and public JVM/KLIB dumps are pinned in
`Scripts/serialization_reference`.

`Scripts/reference_cases/serialization_kinds.kt` exercises every kind's output,
stable hash, singleton identity, alias/FQN access, and hierarchy dispatch. Its
expected output was produced by the real Kotlin 2.3.10 JVM compiler/runtime with
`kotlinx-serialization-core-jvm:1.10.0`; it uses no candidate replacement API.
Compile that fixture with the pinned core JAR from the reference cache:

```bash
kotlinc Scripts/reference_cases/serialization_kinds.kt \
  -classpath /path/to/kotlinx-serialization-core-jvm-1.10.0.jar \
  -d /tmp/serialization-kinds.jar
kotlin -classpath /tmp/serialization-kinds.jar:/path/to/kotlinx-serialization-core-jvm-1.10.0.jar \
  Serialization_kindsKt > /tmp/serialization-kinds.stdout
diff -u Scripts/reference_cases/serialization_kinds.expected /tmp/serialization-kinds.stdout
```

The focused `SerializationKindsTests` runs the same fixture through bundled source
and precompiled stdlib at O0/O2. A separately compiled producer returns a kind to a
`.kklib` consumer, which verifies identity, `toString`/`hashCode` dispatch and type
checks. `SerializationKindSemaTests` checks opt-in and sealed-class diagnostics.
The parent KUU-1724 remains open until all modules and its source/library/native
distribution and compatibility criteria are complete.

The implementation also fixes compiler paths exposed by source O2 and reflection:
reference vararg constructor wrappers retain array parameters; reflected source
functions receive the List representation used by ordinary calls; primitive
arrays retain their representation. `KClass<T>.constructors` retains `T`.
Boxed Channel close callbacks expand into the named function/environment ABI pair.
`annotation_vararg_reflection.kt` and `channel_boxed_close_callback.kt` are minimal
JVM-backed regressions exercised at O0/O2.

Sealed validation visits nested classes, objects and companions and enforces the
stdlib/library module boundary. Annotation literal concatenation is folded from
lexer tokens before metadata reconstruction loses the operand boundaries. The
subclass opt-in diagnostic includes the complete upstream marker message, and the
precompiled marker test verifies targets, severity and that message after export.
