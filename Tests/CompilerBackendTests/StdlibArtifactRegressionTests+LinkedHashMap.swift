@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-1944: subclass declarations, superclass constructor overloads, and
    /// inherited Map members must type-check with source and serialized stdlib.
    /// The exact reproducer must also execute and preserve insertion order.
    @Test(arguments: [false, true])
    func testLinkedHashMapSubclassThroughSourceAndFreshArtifact(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        if let artifactPath {
            let metadata = try Data(contentsOf: URL(fileURLWithPath: artifactPath + "/metadata.bin"))
            let linkedHashMap = try #require(MetadataDecoder().decode(metadata).first {
                $0.kind == .class && $0.fqName == "kotlin.collections.LinkedHashMap"
            })
            #expect(linkedHashMap.isOpenClass)
        }

        let source = try diffCaseSource("linkedhashmap_subclass.kt", file: #filePath) + """

        class CapacityMap : LinkedHashMap<String, Int>(8)
        class LoadFactorMap : LinkedHashMap<String, Int>(8, 0.75f)
        class CopyMap(original: Map<String, Int>) : LinkedHashMap<String, Int>(original)
        class SecondaryMap : LinkedHashMap<String, Int> {
            constructor() : super()
            constructor(capacity: Int) : super(capacity)
            constructor(capacity: Int, factor: Float) : super(capacity, factor)
            constructor(original: Map<String, Int>) : super(original)
        }

        fun inheritedMembers(ordered: OrderedMap) {
            val asLinked: LinkedHashMap<String, Int> = ordered
            val asHash: HashMap<String, Int> = ordered
            val asMutable: MutableMap<String, Int> = ordered
            val asMap: Map<String, Int> = ordered
            val previous: Int? = ordered.put("c", 3)
            val current: Int? = ordered["c"]
            val count: Int = ordered.size
            val entries: MutableSet<MutableMap.MutableEntry<String, Int>> = ordered.entries
            val hasKey: Boolean = ordered.containsKey("c")
            val hasValue: Boolean = ordered.containsValue(3)
            ordered.putAll(mapOf("d" to 4))
            ordered.remove("c")
            ordered.clear()
            val empty: Boolean = ordered.isEmpty()
            val anonymous = object : LinkedHashMap<String, Int>() {}
            CapacityMap()
            LoadFactorMap()
            CopyMap(asMap)
            SecondaryMap()
            SecondaryMap(8)
            SecondaryMap(8, 0.75f)
            SecondaryMap(asMap)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            let context = makeCompilationContext(
                inputs: [path],
                moduleName: "KUU1944LinkedHashMapSubclass",
                emit: .executable,
                outputPath: output,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(context)
            try assertNoDiagnosticErrors(context)
            try LoweringPhase().run(context)
            try CodegenPhase().run(context)
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stdout == "b,a\n2,1\n")
        }
    }
}
