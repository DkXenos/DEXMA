/// The warp shader's parameters. Matches `WarpUniforms` in ScreenWarp.metal (64 bytes).
struct WarpUniforms {
    var size = SIMD2<Float>()
    var scale: Float = 2
    var amount: Float = 0
    var body = SIMD4<Float>()
    var pointer = SIMD4<Float>()
    var reach: Float = 40
    var chroma: Float = 0
    var debug = SIMD2<Float>()
}
