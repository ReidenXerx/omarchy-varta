import Foundation

// Port of plain() and plainly() from app/watchcore.py.

/// A region name is at most a couple of words; anything longer is not one.
public let nameCeiling = 120

/// A string from the feed, fit to hand to anything that draws text.
///
/// Region names end up in the menu bar, in notifications and in the dropdown,
/// so markup, anything unprintable and anything that could rearrange a line are
/// removed here, at the boundary, rather than trusted to each place.
public func plain(_ text: String?) -> String {
    guard let text else { return "" }
    var out = ""
    for scalar in text.unicodeScalars {
        if scalar == "\r" || scalar == "\n" || scalar == "\t" {
            out.unicodeScalars.append(" ")
        } else if isPrintable(scalar) && scalar != "<" && scalar != ">" {
            out.unicodeScalars.append(scalar)
        }
    }
    return String(out.trimmingCharacters(in: .whitespaces).prefix(nameCeiling))
}

/// Python's str.isprintable(): no control, format, separator-other-than-space,
/// unassigned or private-use characters. Format characters (bidi overrides,
/// zero-width joiners) are the ones that can rearrange a line.
private func isPrintable(_ s: Unicode.Scalar) -> Bool {
    switch s.properties.generalCategory {
    case .control, .format, .surrogate, .privateUse, .unassigned,
         .lineSeparator, .paragraphSeparator:
        return false
    case .spaceSeparator:
        return s == " "
    default:
        return true
    }
}

/// What to tell a person about a failure.
///
/// Read by somebody deciding whether to move, at three in the morning, possibly
/// from across a room. A URLError description is a sentence for whoever wrote
/// this, not for them. Whatever it says, it never says something reassuring.
public func plainly(_ error: String?) -> String {
    let text = (error ?? "").lowercased()
    func has(_ needles: String...) -> Bool { needles.contains { text.contains($0) } }
    if has("name resolution", "name or service not known", "temporary failure",
           "errno -2", "errno -3", "not connected to the internet",
           "hostname could not be found", "network connection was lost") {
        return "waiting for the network"
    }
    if has("429", "too often") { return "the feed asked us to slow down" }
    if has("timed out", "timeout") { return "the feed is not answering" }
    if has("refused", "unreachable", "no route", "could not connect") { return "cannot reach the feed" }
    if has("certificate", "ssl", "secure connection") { return "the connection to the feed could not be trusted" }
    if has("http 5") { return "the feed is having trouble" }
    if has("json", "no regions", "too large", "unexpected") { return "the feed sent something unexpected" }
    return "cannot read the feed"
}
