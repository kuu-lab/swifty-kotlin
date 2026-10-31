@testable import CompilerCore
import TestStdlibCache
import Testing

// KUU-3902: a value class stringified through an `Any`/nullable slot must
// print its synthesized rendering once — `IC(s=OK)` — not wrap the
// nominal/tagged box again (`IC(s=IC(s=…))`, which recursed through the
// erased `Any.toString` bridge for reference-backed payloads). Every
// direct-call site — println/print, interpolation, `+` concat, member
// `.toString()`, and data-class property rendering — now normalizes the slot
// receiver via `unboxedValueClassReceiverExpr` before dispatching to the
// class's own toString, matching the JVM byte-for-byte.
@Suite(.serialized)
struct KUU3902BoxedValueClassToStringTests {
    @Test(arguments: [false, true])
    func erasedAndNullableValueClassToStringUnwrapsBoxedReceiver(fromArtifact: Bool) throws {
        if fromArtifact {
            TestStdlibCache.shared.prepare()
        }
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3902_boxed_value_class_tostring.kt", file: #filePath),
            expectedOutput: "IC(s=OK)\nII(i=42)\nS(s=str)\nN(x=nullable)\nN(x=null)\nR(c=H(h))\nD(d=1.5)\nW<w>\nIC(s=direct)\nII(i=7)\nS(s=ds)\nN(x=dn)\nR(c=H(dh))\nD(d=2.5)\nIC(s=nullable-slot)\ninterp: IC(s=nullable-slot)\nconcat: IC(s=nullable-slot)\nIC(s=nullable-slot)\nII(i=9)\ni2: II(i=9)\nII(i=9)\nS(s=ns)\nN(x=nn)\nN(x=null)\nR(c=H(rh))\nDC(v=IC(s=nullable-slot))\nD(d=3.5)\nnull\nnull\n[IC(s=nullable-slot)]\n[IC(s=e)]\nOK\nnullable-slot\ntrue\n",
            moduleName: "KUU3902BoxedValueClassToString",
            allowDefaultStdlibLibrary: fromArtifact,
            expectedStderr: ""
        )
    }
}
