import Foundation

/// One entry of `hostState.displays`. spec §3.4.5: "{`id` int, `x`,`y`,`w`,`h` int (CG global
/// points), `scale` num, `main` bool}".
public struct Display: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int
    public var scale: Double
    public var main: Bool

    public init(id: Int, x: Int, y: Int, w: Int, h: Int, scale: Double, main: Bool) {
        self.id = id
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.scale = scale
        self.main = main
    }
}
