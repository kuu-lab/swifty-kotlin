// KUU-1266: soft keywords are valid label definitions and jump targets.
fun visit(block: () -> Unit) { block() }
fun Int.inner(): Int = this@inner

fun main() {
    inner@ for (i in 1..3) { if (i == 2) break@inner; println(i) }
    println("done")
    var count = 0
    inner@ for (i in 1..3) { for (j in 1..2) { count += 1; break@inner } }
    data@ for (i in 1..3) { for (j in 1..2) { count += 1; break@data } }
    value@ for (i in 1..3) { for (j in 1..2) { count += 1; break@value } }
    lateinit@ for (i in 1..3) { for (j in 1..2) { count += 1; break@lateinit } }
    open@ for (i in 1..3) { for (j in 1..2) { count += 1; break@open } }
    final@ for (i in 1..3) { for (j in 1..2) { count += 1; break@final } }
    abstract@ for (i in 1..3) { for (j in 1..2) { count += 1; break@abstract } }
    sealed@ for (i in 1..3) { for (j in 1..2) { count += 1; break@sealed } }
    enum@ for (i in 1..3) { for (j in 1..2) { count += 1; break@enum } }
    annotation@ for (i in 1..3) { for (j in 1..2) { count += 1; break@annotation } }
    operator@ for (i in 1..3) { for (j in 1..2) { count += 1; break@operator } }
    infix@ for (i in 1..3) { for (j in 1..2) { count += 1; break@infix } }
    inline@ for (i in 1..3) { for (j in 1..2) { count += 1; break@inline } }
    tailrec@ for (i in 1..3) { for (j in 1..2) { count += 1; break@tailrec } }
    vararg@ for (i in 1..3) { for (j in 1..2) { count += 1; break@vararg } }
    const@ for (i in 1..3) { for (j in 1..2) { count += 1; break@const } }
    private@ for (i in 1..3) { for (j in 1..2) { count += 1; break@private } }
    public@ for (i in 1..3) { for (j in 1..2) { count += 1; break@public } }
    internal@ for (i in 1..3) { for (j in 1..2) { count += 1; break@internal } }
    protected@ for (i in 1..3) { for (j in 1..2) { count += 1; break@protected } }
    companion@ for (i in 1..3) { for (j in 1..2) { count += 1; break@companion } }
    init@ for (i in 1..3) { for (j in 1..2) { count += 1; break@init } }
    field@ for (i in 1..3) { for (j in 1..2) { count += 1; break@field } }
    expect@ for (i in 1..3) { for (j in 1..2) { count += 1; break@expect } }
    actual@ for (i in 1..3) { for (j in 1..2) { count += 1; break@actual } }
    crossinline@ for (i in 1..3) { for (j in 1..2) { count += 1; break@crossinline } }
    noinline@ for (i in 1..3) { for (j in 1..2) { count += 1; break@noinline } }
    reified@ for (i in 1..3) { for (j in 1..2) { count += 1; break@reified } }
    out@ for (i in 1..3) { for (j in 1..2) { count += 1; break@out } }
    by@ for (i in 1..3) { for (j in 1..2) { count += 1; break@by } }
    where@ for (i in 1..3) { for (j in 1..2) { count += 1; break@where } }
    file@ for (i in 1..3) { for (j in 1..2) { count += 1; break@file } }
    property@ for (i in 1..3) { for (j in 1..2) { count += 1; break@property } }
    receiver@ for (i in 1..3) { for (j in 1..2) { count += 1; break@receiver } }
    param@ for (i in 1..3) { for (j in 1..2) { count += 1; break@param } }
    delegate@ for (i in 1..3) { for (j in 1..2) { count += 1; break@delegate } }
    catch@ for (i in 1..3) { for (j in 1..2) { count += 1; break@catch } }
    finally@ for (i in 1..3) { for (j in 1..2) { count += 1; break@finally } }
    external@ for (i in 1..3) { for (j in 1..2) { count += 1; break@external } }
    dynamic@ for (i in 1..3) { for (j in 1..2) { count += 1; break@dynamic } }
    import@ for (i in 1..3) { for (j in 1..2) { count += 1; break@import } }
    constructor@ for (i in 1..3) { for (j in 1..2) { count += 1; break@constructor } }
    get@ for (i in 1..3) { for (j in 1..2) { count += 1; break@get } }
    set@ for (i in 1..3) { for (j in 1..2) { count += 1; break@set } }
    suspend@ for (i in 1..3) { for (j in 1..2) { count += 1; break@suspend } }
    override@ for (i in 1..3) { for (j in 1..2) { count += 1; break@override } }
    setparam@ for (i in 1..3) { for (j in 1..2) { count += 1; break@setparam } }
    context@ for (i in 1..3) { for (j in 1..2) { count += 1; break@context } }
    of@ for (i in 1..3) { for (j in 1..2) { count += 1; break@of } }
    header@ for (i in 1..3) { for (j in 1..2) { count += 1; break@header } }
    impl@ for (i in 1..3) { for (j in 1..2) { count += 1; break@impl } }
    it@ for (i in 1..3) { for (j in 1..2) { count += 1; break@it } }
    ordinary@ for (i in 1..3) { for (j in 1..2) { count += 1; break@ordinary } }
    `when`@ for (i in 1..3) { for (j in 1..2) { count += 1; break@`when` } }
    `label name`@ for (i in 1..3) { for (j in 1..2) { count += 1; break@`label name` } }
    println(count)
    var n = 0
    var visits = 0
    data@ while (n < 3) {
        n += 1
        inline@ for (j in 1..2) { visits += 1; continue@data }
    }
    println(n)
    println(visits)
    var d = 0
    try { println("try") } catch (e: Exception) { println("caught") } finally { println("cleanup") }
    finally@ do {
        d += 1
        if (d < 2) continue@finally
        break@finally
    } while (true)
    println(d)
    visit catch@{ println("lambda"); return@catch; println("unreachable") }
    val action = import@{ return@import 7 }
    println(action())
    println(9.inner())
}
