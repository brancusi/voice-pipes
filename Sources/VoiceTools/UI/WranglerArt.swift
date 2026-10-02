import SwiftUI

/// The Wrangler, the Voice Pipes mascot: 20 × 30 pixels in three poses, converted exactly from the design
/// system's Mascot SVGs (Assets → Mascot). Each letter is one palette colour; `.` is transparent. Never edit by
/// hand: regenerate from the SVGs so the app and the design system stay identical.
enum WranglerArt {
    enum Pose: CaseIterable { case busk, sing, done }

    static let width = 20, height = 30

    static let palette: [Character: UInt32] = [
        "a": 0x18140F,
        "b": 0x8A5A3C,
        "c": 0x4A3F35,
        "d": 0x8FB8D6,
        "e": 0x5E3D29,
        "f": 0xB97C5C,
        "g": 0xB8A88E,
        "h": 0xE3A983,
        "i": 0xE0694A,
        "j": 0xD8D0C0,
        "k": 0xEC8F7C,
        "l": 0xC3A3D4,
        "m": 0x5C4030,
        "n": 0x8F74A3,
        "o": 0xE8C26A,
        "p": 0xA9BF8A,
        "q": 0x3D5873,
        "r": 0x2C4257,
        "s": 0x7A4B30,
        "t": 0xC99A6E,
        "u": 0xF6D58A,
    ]

    static func rows(_ pose: Pose) -> [String] {
        switch pose {
        case .busk: busk
        case .sing: sing
        case .done: done
        }
    }

    private static let busk = [
        "......aaaaaaaa......",
        ".....abbbbbbbba.....",
        ".....abcddcddca.....",
        ".....aeeeeeeeea.....",
        ".aaaabbbbbbbbbbaaaa.",
        "abbbbbbbbbbbbbbbbbba",
        ".aaaaaaaaaaaaaaaaaa.",
        ".....affffffffa.....",
        "....gahahhhhaha.....",
        "....gahhhhfhhha.....",
        "....gaheeeeeeha.....",
        "....ggijjjjjjjjja...",
        ".....aaajajajaja....",
        "....akkkkkkkkkka....",
        "...allakkkkkkalla...",
        "..allmmmakkammmlla..",
        ".alllmmmllllmmmllla.",
        ".allammmllllmmmalla.",
        ".allammmlnllmmmalla.",
        ".ahhammmllllmmmahha.",
        ".ahhaaaaooooaaaahha.",
        ".ppaqqqqqqqqqqagg...",
        ".p.aqqqqqrqqqqag....",
        "...aqqqqaaqqqqa.....",
        "...aqqqa..aqqqa.....",
        "...asssa..asssa.....",
        "...astsa..astsa.....",
        "..assssa..assssa....",
        ".asssssaj.jasssssa..",
        "aaaaa.aa..aa.aaaaa..",
    ]

    private static let sing = [
        "......aaaaaaaa....pp",
        ".....abbbbbbbba...pp",
        ".....abcddcddca...p.",
        ".....aeeeeeeeea.ppp.",
        ".aaaabbbbbbbbbbappa.",
        "abbbbbbbbbbbbbbbbbba",
        ".aaaaaaaaaaaaaaaaaa.",
        ".....affffffffa.....",
        "....gahhhhhhhha.....",
        "....gahaahfaaha.....",
        "....gaheeeeeeha.....",
        "....ggihhaahhha.....",
        ".....aahhaahhaa.....",
        "....akkkkkkkkkka....",
        "...allakkkkkkalla...",
        "..allmmmakkammmlla..",
        ".alllmmmllllmmmllla.",
        ".allammmllllmmmalla.",
        ".allammmlnllmmmalla.",
        ".ahhammmllllmmmahha.",
        ".ahhaaaaooooaaaahha.",
        ".ppaqqqqqqqqqqagg...",
        ".p.aqqqqqrqqqqag....",
        "...aqqqqaaqqqqa.....",
        "...aqqqa..aqqqa.....",
        "...asssa..asssa.....",
        "...astsa..astsa.....",
        "..assssa..assssa....",
        ".asssssaj.jasssssa..",
        "aaaaa.aa..aa.aaaaa..",
    ]

    private static let done = [
        "......aaaaaaaa......",
        ".....abbbbbbbba.....",
        ".....abcddcddca.....",
        ".....aeeeeeeeea.....",
        ".aaaabbbbbbbbbbaaaa.",
        "abbbbbbbbbbbbbbbbbba",
        ".aaaaaaaaaaaaaaaaaa.",
        ".....affffffffa.....",
        "....gahahhhaaha...u.",
        "....gahhhhfhhha..uuu",
        "....gaheeeeeeha...u.",
        "....ggihahhahha.....",
        ".....aahhaahhaa.....",
        "....akkkkkkkkkka....",
        "...allakkkkkkalla...",
        "..allmmmakkammmlla..",
        ".alllmmmllllmmmllla.",
        ".allammmllllmmmalla.",
        ".allammmlnllmmmalla.",
        ".ahhammmllllmmmahha.",
        ".ahhaaaaooooaaaahha.",
        ".ppaqqqqqqqqqqagg...",
        ".p.aqqqqqrqqqqag....",
        "...aqqqqaaqqqqa.....",
        "...aqqqa..aqqqa.....",
        "...asssa..asssa.....",
        "...astsa..astsa.....",
        "..assssa..assssa....",
        ".asssssaj.jasssssa..",
        "aaaaa.aa..aa.aaaaa..",
    ]
}
