package java.net

/** Native source-backed compatibility type for JVM-shaped URI signatures. */
public class URI(private val spec: String) {
    public override fun toString(): String = spec
}
