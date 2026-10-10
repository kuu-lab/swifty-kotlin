@testable import Runtime
import Testing

private func reflectedAnnotationFactory(_ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = 0
    return kk_object_new(0, 73101)
}

private func throwingAnnotationFactory(_ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "annotation factory")
    return runtimeNullSentinelInt
}

@Suite(.runtimeIsolation(.metadataOnly))
struct RuntimeTypedAnnotationFactoryTests {
    private func klass(_ name: String) -> (Int, Int) {
        let token = Int(truncatingIfNeeded: (runtimeStableNominalTypeID(fqName: name) << 9) | 6)
        _ = __kk_kclass_register_metadata(token, runtimeMakeStringRaw(name), runtimeMakeStringRaw(name), 0, 0, 0, 0, 0)
        return (token, __kk_kclass_create(token, 0))
    }

    @Test func materializesActualObjectsAndPreservesRecordsAcrossRegistration() throws {
        let (token, value) = klass("sample.TaggedFactory")
        let bridge: KKThunkEntryPoint = reflectedAnnotationFactory
        for _ in 0..<2 {
            _ = __kk_kclass_register_annotation_factory(token, runtimeMakeStringRaw("sample.Named"), 0, 0,
                                                        unsafeBitCast(bridge, to: Int.self))
        }
        _ = klass("sample.TaggedFactory")
        var thrown = 0
        for _ in 0..<2 {
            let list = try #require(runtimeReflectionObject(from: __kk_kclass_get_annotations_typed(value, &thrown),
                                                            as: RuntimeListBox.self))
            #expect(thrown == 0)
            #expect(list.elements.count == 1)
            #expect(runtimeReflectionObject(from: try #require(list.elements.first), as: RuntimeObjectBox.self) != nil)
        }
        let found = __kk_kclass_find_annotation_typed(value, (73101 << 9) | 6, &thrown)
        #expect(runtimeReflectionObject(from: found, as: RuntimeObjectBox.self) != nil)
        #expect(__kk_kclass_find_annotation_typed(value, (73102 << 9) | 6, &thrown) == runtimeNullSentinelInt)
        // The pre-existing ABI retains its legacy record representation.
        let legacy = try #require(runtimeReflectionObject(from: __kk_kclass_get_annotations(value), as: RuntimeListBox.self))
        #expect(runtimeReflectionObject(from: try #require(legacy.elements.first), as: RuntimeAnnotationBox.self) != nil)
    }

    @Test func factoryExceptionsReachBothReflectionOperations() {
        let (token, value) = klass("sample.ThrowingFactory")
        let bridge: KKThunkEntryPoint = throwingAnnotationFactory
        _ = __kk_kclass_register_annotation_factory(token, runtimeMakeStringRaw("sample.Throwing"), 0, 0,
                                                    unsafeBitCast(bridge, to: Int.self))
        var thrown = 0
        #expect(__kk_kclass_get_annotations_typed(value, &thrown) == runtimeNullSentinelInt)
        #expect(thrown != 0)
        thrown = 0
        #expect(__kk_kclass_find_annotation_typed(value, (73101 << 9) | 6, &thrown) == runtimeNullSentinelInt)
        #expect(thrown != 0)
    }

    @Test func legacyMetadataReregistrationDoesNotAccumulateAnnotations() throws {
        let (token, value) = klass("sample.LegacyFactory")
        for _ in 0..<3 {
            _ = klass("sample.LegacyFactory")
            _ = __kk_kclass_register_single_annotation(token, runtimeMakeStringRaw("sample.Legacy"), 0, 0)
            let list = try #require(runtimeReflectionObject(from: __kk_kclass_get_annotations(value), as: RuntimeListBox.self))
            #expect(list.elements.count == 1)
        }
    }

    @Test func factoryAndLegacyRegistrationsShareTheSameAnnotationValue() throws {
        let (token, value) = klass("sample.MixedFactory")
        let bridge: KKThunkEntryPoint = reflectedAnnotationFactory
        let name = runtimeMakeStringRaw("sample.Named")
        _ = __kk_kclass_register_single_annotation(token, name, 0, 0)
        _ = __kk_kclass_register_annotation_factory(token, name, 0, 0, unsafeBitCast(bridge, to: Int.self))
        _ = klass("sample.MixedFactory")
        _ = __kk_kclass_register_single_annotation(token, name, 0, 0)
        var thrown = 0
        let list = try #require(runtimeReflectionObject(from: __kk_kclass_get_annotations_typed(value, &thrown), as: RuntimeListBox.self))
        #expect(thrown == 0 && list.elements.count == 1)
        #expect(runtimeReflectionObject(from: try #require(list.elements.first), as: RuntimeObjectBox.self) != nil)
        // A repeatable occurrence with different arguments remains distinct.
        runtimeKClassMetadataRegistry.appendAnnotations(typeToken: token,
            annotations: [RuntimeAnnotationRecord(annotationFQName: "sample.Named", arguments: ["different"])])
        #expect(runtimeKClassMetadataRegistry.lookup(typeToken: token)?.annotations.count == 2)
    }

    @Test func callableFactoriesPropagateExceptionsAndKeepLegacyRecords() throws {
        let raw = registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: 0, closureRaw: 0, arity: 0))
        _ = kk_callable_ref_tag_kfunction(raw, runtimeMakeStringRaw("marked"), 0, 0, 0)
        let empty = registerRuntimeObject(RuntimeListBox(elements: []))
        _ = __kk_kcallable_register(raw, 0, 0, empty, empty, 1, 0, 0, empty)
        let bridge: KKThunkEntryPoint = reflectedAnnotationFactory
        _ = __kk_kcallable_register_annotation_factory(raw, runtimeMakeStringRaw("sample.Named"), 0, 0,
                                                       unsafeBitCast(bridge, to: Int.self))
        _ = __kk_kcallable_register_single_annotation(raw, runtimeMakeStringRaw("sample.Named"), 0, 0)
        var thrown = 0
        let list = try #require(runtimeReflectionObject(from: __kk_kcallable_get_annotations_typed(raw, &thrown),
                                                        as: RuntimeListBox.self))
        #expect(thrown == 0 && list.elements.count == 1)
        #expect(runtimeReflectionObject(from: try #require(list.elements.first), as: RuntimeObjectBox.self) != nil)
        let throwing: KKThunkEntryPoint = throwingAnnotationFactory
        _ = __kk_kcallable_register_annotation_factory(raw, runtimeMakeStringRaw("sample.Throwing"), 0, 0,
                                                       unsafeBitCast(throwing, to: Int.self))
        #expect(__kk_kcallable_get_annotations_typed(raw, &thrown) == runtimeNullSentinelInt)
        #expect(thrown != 0)
    }
}
