package kuu2628.pathboundaryconsumer

import kotlinx.io.files.Path
import kuu2628.pathboundary.pathParentFromProducer

fun main() {
    val base: Path = Path("base")
    val fromStringParts: Path = Path("base", "child")
    val fromPathParts: Path = Path(base, "child")
    val nullableParent: Path? = fromPathParts.parent
    val forwardedParent: Path? = pathParentFromProducer(fromPathParts)
    check(base.toString() == "base")
    check(fromStringParts.toString() == "base/child")
    check(fromPathParts.toString() == "base/child")
    check(nullableParent?.toString() == "base")
    check(forwardedParent?.toString() == "base")
    println("PATH_PUBLIC_SURFACE_OK")
}
