import kotlin.io.path.Path
import kotlin.io.path.visitFileTree

fun visitWithAllParams(path: Path) {
    path.visitFileTree(maxDepth = 5, followLinks = true) {
    }
}

fun visitWithFollowLinksDefault(path: Path) {
    path.visitFileTree(maxDepth = 3, followLinks = false) {
    }
}
