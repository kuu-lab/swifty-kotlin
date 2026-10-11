# SerialDescriptor contract

KUU-1740 adds the complete `SerialDescriptor.kt` source from serialization 1.10.0,
commit `370c4e3780066b82f746cf38e4733cbe62c94f74`. The provenance manifest records
its Git blob and upstream/local SHA-256. Only two imports used in documentation
are removed; interface members, default getters, iterable implementations,
annotations and copyright are retained. The pinned Apache license is in
`Scripts/serialization_reference`.

The interface describes name, kind, nullability, inline status, element count,
class annotations, element names/indices/annotations/descriptors and optionality.
It retains the default false getters and empty annotation list. Its
`SubclassOptInRequired(SealedSerializationApi)` contract controls custom
implementations. `elementNames` and `elementDescriptors` create independent
iterators and delegate element access to the descriptor.

`Scripts/reference_cases/serialization_descriptor.kt` is an executable example
with two custom descriptor implementations and annotation instances. Its 15-line
expected output was produced using actual Kotlin JVM 2.3.10 and the pinned
`kotlinx-serialization-core-jvm:1.10.0` artifact. It checks interface dispatch,
alias and fully qualified interface types, default and overridden getters, annotations, order, identity, independent
iterators, exhaustion and descriptor exceptions.

```bash
kotlinc Scripts/reference_cases/serialization_descriptor.kt \
  -classpath /path/to/kotlinx-serialization-core-jvm-1.10.0.jar \
  -d /tmp/serialization-descriptor.jar
kotlin -classpath /tmp/serialization-descriptor.jar:/path/to/kotlinx-serialization-core-jvm-1.10.0.jar \
  Serialization_descriptorKt > /tmp/serialization-descriptor.stdout
diff -u Scripts/reference_cases/serialization_descriptor.expected /tmp/serialization-descriptor.stdout
```

`SerializationDescriptorTests` uses bundled source and prebuilt stdlib at O0/O2,
then compiles the implementations into a separate `.kklib` consumed through the
interface without consumer opt-in. Source/prebuilt frontend cases check the subclass marker with and
without opt-in. The separate JVM producer/consumer has also been executed against
the same upstream core artifact and expected output.

The iterator bodies exposed a compiler bug: a bare property of an outer
interface receiver was dispatched on the anonymous iterator itself. Sema now
records the selected receiver tower entry for bare reads; object and lambda
capture discovery retains that receiver, and KIR reads it after capture
restoration. `captured_interface_property_receiver.kt` fixes the independent
property-only object/lambda paths, live getters and inner-property shadowing
as a regression contract.

Descriptor factories/builders, serializer generation, codecs, formats and the
full upstream/Native/macOS validation remain with parent KUU-1724.
