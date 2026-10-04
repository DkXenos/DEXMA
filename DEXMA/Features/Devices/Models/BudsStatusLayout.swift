/// Where the batteries are in one status message's payload (byte offsets). Levels are 0–100;
/// anything else (the case sends 101 while no bud is in it) means unknown. `placement` is a
/// byte with the left bud in the high nibble and the right in the low one (0 = not connected,
/// 1 wearing, 2 out, 3 in the case, 4 in the closed case); `charging` a bit field (0x10 left,
/// 0x04 right, 0x01 case).
nonisolated struct BudsStatusLayout: Equatable {
    var left: Int
    var right: Int
    var placement: Int?
    var caseLevel: Int?
    var charging: Int?
}
