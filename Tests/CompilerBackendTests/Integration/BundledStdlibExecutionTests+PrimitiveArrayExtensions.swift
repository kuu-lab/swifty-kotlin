import Foundation
import Testing

extension BundledStdlibExecutionTests {
    // KUU-1105: exercise exact primitive types through source and imported metadata.
    @Test(arguments: [true, false])
    func testPrimitiveArrayExtensions(allowDefaultStdlibLibrary: Bool) throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/primitive_array_extensions.kt"
        ), encoding: .utf8)
        try compileAndRunKotlin(
            source,
            expectedOutput: """
            7
            [(9, 1)]
            2
            [10]
            2
            []
            1
            Int
            [1, 2, 1]
            [3, 1, 2]
            [3, 1]
            [2, 1]
            [1, 2]
            [2, 3, 2]
            null
            1
            3
            3:1:2:1:end
            3
            [seed, 3, 1, 2, 1]
            [3]
            [3, 1, 2, 1]
            3
            [3, 1, 2]
            [3, 1, 1, 2]
            [1, 1, 2, 3]
            ([3], [1, 2, 1])
            {true=[3], false=[1, 2, 1]}
            {true=[3], false=[1, 2, 1]}
            {3=3, 1=1, 2=2}
            {3=3, 1=1, 2=2}
            {3=true, 1=false, 2=false}
            [(3, 3), (1, 1), (2, 2), (1, 1)]
            [(3, x), (1, y)]
            [(3, x), (1, y)]
            [3:3, 1:1, 2:2, 1:1]
            [3:x, 1:y]
            [3:x, 1:y]
            1
            3
            3
            1
            3
            1
            null
            null
            1.75
            true
            0:3
            1:1
            2:2
            3:1
            [3, 1, 1, 1]
            [1, 1, 1, 1]
            Long
            [1, 2, 1]
            [3, 1, 2]
            [3, 1]
            [2, 1]
            [1, 2]
            [2, 3, 2]
            null
            1
            3
            3:1:2:1:end
            3
            [seed, 3, 1, 2, 1]
            [3]
            [3, 1, 2, 1]
            3
            [3, 1, 2]
            [3, 1, 1, 2]
            [1, 1, 2, 3]
            ([3], [1, 2, 1])
            {true=[3], false=[1, 2, 1]}
            {true=[3], false=[1, 2, 1]}
            {3=3, 1=1, 2=2}
            {3=3, 1=1, 2=2}
            {3=true, 1=false, 2=false}
            [(3, 3), (1, 1), (2, 2), (1, 1)]
            [(3, x), (1, y)]
            [(3, x), (1, y)]
            [3:3, 1:1, 2:2, 1:1]
            [3:x, 1:y]
            [3:x, 1:y]
            1
            3
            3
            1
            3
            1
            null
            null
            1.75
            true
            0:3
            1:1
            2:2
            3:1
            [3, 1, 1, 1]
            [1, 1, 1, 1]
            Byte
            [1, 2, 1]
            [3, 1, 2]
            [3, 1]
            [2, 1]
            [1, 2]
            [2, 3, 2]
            null
            1
            3
            3:1:2:1:end
            3
            [seed, 3, 1, 2, 1]
            [3]
            [3, 1, 2, 1]
            3
            [3, 1, 2]
            [3, 1, 1, 2]
            [1, 1, 2, 3]
            ([3], [1, 2, 1])
            {true=[3], false=[1, 2, 1]}
            {true=[3], false=[1, 2, 1]}
            {3=3, 1=1, 2=2}
            {3=3, 1=1, 2=2}
            {3=true, 1=false, 2=false}
            [(3, 3), (1, 1), (2, 2), (1, 1)]
            [(3, x), (1, y)]
            [(3, x), (1, y)]
            [3:3, 1:1, 2:2, 1:1]
            [3:x, 1:y]
            [3:x, 1:y]
            1
            3
            3
            1
            3
            1
            null
            null
            1.75
            true
            0:3
            1:1
            2:2
            3:1
            [3, 1, 1, 1]
            [1, 1, 1, 1]
            Short
            [1, 2, 1]
            [3, 1, 2]
            [3, 1]
            [2, 1]
            [1, 2]
            [2, 3, 2]
            null
            1
            3
            3:1:2:1:end
            3
            [seed, 3, 1, 2, 1]
            [3]
            [3, 1, 2, 1]
            3
            [3, 1, 2]
            [3, 1, 1, 2]
            [1, 1, 2, 3]
            ([3], [1, 2, 1])
            {true=[3], false=[1, 2, 1]}
            {true=[3], false=[1, 2, 1]}
            {3=3, 1=1, 2=2}
            {3=3, 1=1, 2=2}
            {3=true, 1=false, 2=false}
            [(3, 3), (1, 1), (2, 2), (1, 1)]
            [(3, x), (1, y)]
            [(3, x), (1, y)]
            [3:3, 1:1, 2:2, 1:1]
            [3:x, 1:y]
            [3:x, 1:y]
            1
            3
            3
            1
            3
            1
            null
            null
            1.75
            true
            0:3
            1:1
            2:2
            3:1
            [3, 1, 1, 1]
            [1, 1, 1, 1]
            Char
            [a, b, a]
            [c, a, b]
            [c, a]
            [b, a]
            [a, b]
            [b, c, b]
            null
            a
            c
            c:a:b:a:end
            c
            [seed, c, a, b, a]
            [c]
            [c, a, b, a]
            3
            [c, a, b]
            [c, a, a, b]
            [a, a, b, c]
            ([c], [a, b, a])
            {true=[c], false=[a, b, a]}
            {true=[c], false=[a, b, a]}
            {c=c, a=a, b=b}
            {c=c, a=a, b=b}
            {c=true, a=false, b=false}
            [(c, c), (a, a), (b, b), (a, a)]
            [(c, x), (a, y)]
            [(c, x), (a, y)]
            [c:c, a:a, b:b, a:a]
            [c:x, a:y]
            [c:x, a:y]
            1
            3
            c
            a
            c
            a
            null
            null
            0:c
            1:a
            2:b
            3:a
            [c, a, a, a]
            [a, a, a, a]
            Boolean
            [false, true, false]
            [true, false, true]
            [true, false]
            [true, false]
            [false, true]
            [true, true, true]
            null
            false
            true
            true:false:true:false:end
            true
            [seed, true, false, true, false]
            [true, true]
            [true, false, true, false]
            2
            [true, false]
            [true, true, false, false]
            [false, false, true, true]
            ([true, true], [false, false])
            {true=[true, true], false=[false, false]}
            {true=[true, true], false=[false, false]}
            {true=true, false=false}
            {true=true, false=false}
            {true=true, false=false}
            [(true, true), (false, false), (true, true), (false, false)]
            [(true, x), (false, y)]
            [(true, x), (false, y)]
            [true:true, false:false, true:true, false:false]
            [true:x, false:y]
            [true:x, false:y]
            1
            3
            0:true
            1:false
            2:true
            3:false
            [true, false, false, false]
            [false, false, false, false]
            Float
            [1.0, 2.0, 1.0]
            [3.0, 1.0, 2.0]
            [3.0, 1.0]
            [2.0, 1.0]
            [1.0, 2.0]
            [2.0, 3.0, 2.0]
            null
            1.0
            3.0
            3.0:1.0:2.0:1.0:end
            3.0
            [seed, 3.0, 1.0, 2.0, 1.0]
            [3.0]
            [3.0, 1.0, 2.0, 1.0]
            3
            [3.0, 1.0, 2.0]
            [3.0, 1.0, 1.0, 2.0]
            [1.0, 1.0, 2.0, 3.0]
            ([3.0], [1.0, 2.0, 1.0])
            {true=[3.0], false=[1.0, 2.0, 1.0]}
            {true=[3.0], false=[1.0, 2.0, 1.0]}
            {3.0=3.0, 1.0=1.0, 2.0=2.0}
            {3.0=3.0, 1.0=1.0, 2.0=2.0}
            {3.0=true, 1.0=false, 2.0=false}
            [(3.0, 3.0), (1.0, 1.0), (2.0, 2.0), (1.0, 1.0)]
            [(3.0, x), (1.0, y)]
            [(3.0, x), (1.0, y)]
            [3.0:3.0, 1.0:1.0, 2.0:2.0, 1.0:1.0]
            [3.0:x, 1.0:y]
            [3.0:x, 1.0:y]
            3.0
            1.0
            3.0
            1.0
            null
            null
            1.75
            true
            0:3.0
            1:1.0
            2:2.0
            3:1.0
            [3.0, 1.0, 1.0, 1.0]
            [1.0, 1.0, 1.0, 1.0]
            Double
            [1.0, 2.0, 1.0]
            [3.0, 1.0, 2.0]
            [3.0, 1.0]
            [2.0, 1.0]
            [1.0, 2.0]
            [2.0, 3.0, 2.0]
            null
            1.0
            3.0
            3.0:1.0:2.0:1.0:end
            3.0
            [seed, 3.0, 1.0, 2.0, 1.0]
            [3.0]
            [3.0, 1.0, 2.0, 1.0]
            3
            [3.0, 1.0, 2.0]
            [3.0, 1.0, 1.0, 2.0]
            [1.0, 1.0, 2.0, 3.0]
            ([3.0], [1.0, 2.0, 1.0])
            {true=[3.0], false=[1.0, 2.0, 1.0]}
            {true=[3.0], false=[1.0, 2.0, 1.0]}
            {3.0=3.0, 1.0=1.0, 2.0=2.0}
            {3.0=3.0, 1.0=1.0, 2.0=2.0}
            {3.0=true, 1.0=false, 2.0=false}
            [(3.0, 3.0), (1.0, 1.0), (2.0, 2.0), (1.0, 1.0)]
            [(3.0, x), (1.0, y)]
            [(3.0, x), (1.0, y)]
            [3.0:3.0, 1.0:1.0, 2.0:2.0, 1.0:1.0]
            [3.0:x, 1.0:y]
            [3.0:x, 1.0:y]
            3.0
            1.0
            3.0
            1.0
            null
            null
            1.75
            true
            0:3.0
            1:1.0
            2:2.0
            3:1.0
            [3.0, 1.0, 1.0, 1.0]
            [1.0, 1.0, 1.0, 1.0]
            []
            []
            []
            empty reduce
            empty min
            empty max
            negative take
            negative drop
            fill order
            fill lower:Array index out of range: -1
            fill upper:Array index out of range: 1
            2
            [1, 9]
            true
            [seed, 1, 2]
            true
            true
            -Infinity
            Infinity
            true
            true
            -Infinity
            Infinity
            [1, 2]
            [a, b]

            """,
            moduleName: "KUU1105PrimitiveArrayExtensions",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testPrimitiveArrayUserExtensions(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun IntArray.indexOf(value: String): String = value
            fun IntArray.lastIndexOf(value: String): String = value
            fun IntArray.fill(value: String): String = value
            fun IntArray.sortedBy(value: String): String = value
            fun IntArray.sortedWith(value: String): String = value

            fun main() {
                val a = intArrayOf(3, 1, 2)
                println(a.indexOf("user index"))
                println(a.lastIndexOf("user last index"))
                println(a.fill("user fill"))
                println(a.sortedBy("user sortedBy"))
                println(a.sortedWith("user sortedWith"))
                println(a.indexOf(1))
                println(a.lastIndexOf(1))
                println(a.sortedBy { it })
                println(a.sortedWith(compareBy { it }))
                a.fill(4, 0, 1)
                println(a.toList())
            }
            """,
            expectedOutput: """
            user index
            user last index
            user fill
            user sortedBy
            user sortedWith
            1
            1
            [1, 2, 3]
            [1, 2, 3]
            [4, 1, 2]

            """,
            moduleName: "KUU1105PrimitiveArrayUserExtensions",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    // KUU-1383: getOrNull/elementAtOrElse/elementAt/single/singleOrNull/
    // indexOfFirst/indexOfLast/toSet for every primitive array type.
    @Test(arguments: [true, false])
    func testPrimitiveArrayMissingExtensions(allowDefaultStdlibLibrary: Bool) throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/primitive_array_missing_extensions.kt"
        ), encoding: .utf8)
        try compileAndRunKotlin(
            source,
            expectedOutput: """
            Int
            2
            1
            null
            null
            2
            9
            -1
            5
            5
            null
            null
            2
            2
            null
            null
            2
            -1
            3
            -1
            [3, 1, 2]
            elementAt-oob
            NSEE:Array is empty.
            IAE:Array has more than one element.
            IAE-p:Array contains more than one matching element.
            NSEE-p:Array contains no element matching the predicate.
            Long
            2
            1
            null
            null
            2
            9
            -1
            5
            5
            null
            null
            2
            2
            null
            null
            2
            -1
            3
            -1
            [3, 1, 2]
            elementAt-oob
            NSEE:Array is empty.
            IAE:Array has more than one element.
            IAE-p:Array contains more than one matching element.
            NSEE-p:Array contains no element matching the predicate.
            Byte
            2
            1
            null
            null
            2
            9
            -1
            5
            5
            null
            null
            2
            2
            null
            null
            2
            -1
            3
            -1
            [3, 1, 2]
            elementAt-oob
            NSEE:Array is empty.
            IAE:Array has more than one element.
            IAE-p:Array contains more than one matching element.
            NSEE-p:Array contains no element matching the predicate.
            Short
            2
            1
            null
            null
            2
            9
            -1
            5
            5
            null
            null
            2
            2
            null
            null
            2
            -1
            3
            -1
            [3, 1, 2]
            elementAt-oob
            NSEE:Array is empty.
            IAE:Array has more than one element.
            IAE-p:Array contains more than one matching element.
            NSEE-p:Array contains no element matching the predicate.
            Char
            b
            a
            null
            null
            b
            q
            z
            e
            e
            null
            null
            b
            b
            null
            null
            2
            -1
            3
            -1
            [c, a, b]
            elementAt-oob
            NSEE:Array is empty.
            IAE:Array has more than one element.
            IAE-p:Array contains more than one matching element.
            NSEE-p:Array contains no element matching the predicate.
            Boolean
            false
            false
            null
            null
            false
            true
            false
            true
            true
            null
            null
            false
            false
            null
            null
            1
            -1
            0
            -1
            [true, false]
            elementAt-oob
            NSEE:Array is empty.
            IAE:Array has more than one element.
            IAE-p:Array contains more than one matching element.
            NSEE-p:Array contains no element matching the predicate.
            Float
            2.0
            1.0
            null
            null
            2.0
            9.0
            -1.0
            5.0
            5.0
            null
            null
            2.0
            2.0
            null
            null
            2
            -1
            3
            -1
            [3.0, 1.0, 2.0]
            elementAt-oob
            NSEE:Array is empty.
            IAE:Array has more than one element.
            IAE-p:Array contains more than one matching element.
            NSEE-p:Array contains no element matching the predicate.
            Double
            2.0
            1.0
            null
            null
            2.0
            9.0
            -1.0
            5.0
            5.0
            null
            null
            2.0
            2.0
            null
            null
            2
            -1
            3
            -1
            [3.0, 1.0, 2.0]
            elementAt-oob
            NSEE:Array is empty.
            IAE:Array has more than one element.
            IAE-p:Array contains more than one matching element.
            NSEE-p:Array contains no element matching the predicate.
            UInt
            2
            1
            null
            null
            2
            9
            0
            5
            5
            null
            null
            2
            2
            null
            null
            2
            -1
            3
            -1
            [3, 1, 2]
            elementAt-oob
            NSEE:Array is empty.
            IAE:Array has more than one element.
            IAE-p:Array contains more than one matching element.
            NSEE-p:Array contains no element matching the predicate.
            ULong
            2
            1
            null
            null
            2
            9
            0
            5
            5
            null
            null
            2
            2
            null
            null
            2
            -1
            3
            -1
            [3, 1, 2]
            elementAt-oob
            NSEE:Array is empty.
            IAE:Array has more than one element.
            IAE-p:Array contains more than one matching element.
            NSEE-p:Array contains no element matching the predicate.
            UByte
            2
            1
            null
            null
            2
            9
            9
            5
            5
            null
            null
            2
            2
            null
            null
            2
            -1
            3
            -1
            [3, 1, 2]
            elementAt-oob
            NSEE:Array is empty.
            IAE:Array has more than one element.
            IAE-p:Array contains more than one matching element.
            NSEE-p:Array contains no element matching the predicate.
            UShort
            2
            1
            null
            null
            2
            9
            9
            5
            5
            null
            null
            2
            2
            null
            null
            2
            -1
            3
            -1
            [3, 1, 2]
            elementAt-oob
            NSEE:Array is empty.
            IAE:Array has more than one element.
            IAE-p:Array contains more than one matching element.
            NSEE-p:Array contains no element matching the predicate.

            """,
            moduleName: "KUU1383PrimitiveArrayMissingExtensions",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
