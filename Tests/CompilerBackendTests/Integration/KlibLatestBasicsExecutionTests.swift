@testable import CompilerCore
import Foundation
import Testing

@Suite
struct KlibLatestBasicsExecutionTests {
    @Test(arguments: [0, 2])
    func executesLatestNativeKlibDefaultsAndStrings(optimization: Int) throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/basics.klib").path
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let source = directory.appendingPathComponent("main.kt")
        let output = directory.appendingPathComponent("main").path
        try """
        import kliblatest.*

        class Consumer : Base() {
            override fun number(value: Int): Int = value + 10
        }

        fun main() {
            println(add(3, 4))
            println(choose(true, 11, 22))
            println(choose(false, 11, 22))
            println(defaults())
            println(defaults(first = 10))
            println(defaults(second = 30))
            println(callDefaults())
            println(callOffset())
            println(8.offset())
            println(count())
            println(count(4, 5))
            println(callEmptyVararg())
            println(callNonEmptyVararg())
            val counter = Counter()
            println(counter.start)
            println(counter.value)
            println(counter.increase())
            println(counter.increase(5))
            println(callCounterDefaults())
            println(callVirtualDefault())
            println(Derived().directSuper())
            println(Derived().number())
            println(callDerivedDefault())
            println(Consumer().number())
            println(callManyDefaults())
            val many: ManyBase = ManyDerived()
            println(many.many())
            println(many.many(p30 = 5))
            println(callKeep())
            println(callKeep() is Int)
            println(callGenericKeep())
            println(callPrimitiveReceiver())
            println(callHeld())
            println(once(100))
            println(once())
            println(once())
            println(callInternal())
            println(acrossFile(8))
            println(crossFileInt())
            println(crossFileLong())
            println(identity("generic"))
            println(highSurrogate().length)
            println(highSurrogate()[0].code)
            println(lowSurrogate()[0].code)
            println(markers().length)
            println(markers()[0].code)
            println(markers()[1].code)
            println(supplementary().length)
            println(supplementary()[0].code)
            println(supplementary()[1].code)
            println(embeddedNull().length)
            println(embeddedNull()[1].code)
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        let result = makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "LatestKlibBasics", inputs: [source.path], outputPath: output,
            emit: .executable, searchPaths: [fixture], target: defaultTargetTriple(),
            optLevel: optimization == 0 ? .O0 : .O2
        ))
        try assertCompilationSucceeded(result, context: "Kotlin 2.4.21 KLIB basic execution")
        #expect(!result.diagnostics.contains {
            ["KSWIFTK-LIB-0027", "KSWIFTK-LIB-0028", "KSWIFTK-LIB-0029"].contains($0.code)
        })
        let run = try CommandRunner.run(executable: output, arguments: [])
        #expect(run.exitCode == 0, "\(run.stderr)")
        #expect(run.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
        7
        11
        22
        19
        25
        37
        37
        8
        11
        0
        2
        0
        3
        10
        10
        12
        17
        12
        14
        20
        14
        14
        23
        130
        130
        105
        42
        true
        44
        true
        45
        100
        1
        2
        42
        50
        101
        202
        generic
        1
        55296
        56320
        2
        59392
        57344
        2
        55357
        56832
        3
        0

        """)
    }
}
