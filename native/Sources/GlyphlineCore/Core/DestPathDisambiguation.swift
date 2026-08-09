// Collision-safe destination naming — originally BatchConvertPanel's private
// uniqueDestPath (for output FILE names within one chosen folder); promoted
// here as a public pure function so the delivery pipeline can reuse the same
// algorithm for output FOLDER names too (two source subtitle files from
// different scanned subfolders routinely share a basename — "episode.srt" in
// every show's own folder is completely normal).

import Foundation

/// The natural `dir/base(.ext)` path, unless something already claimed it
/// THIS run — then disambiguated by prefixing the source file's own parent
/// folder name ("ep01_subtitle.srt" vs "ep02_subtitle.srt"), and if even THAT
/// collides (two source folders sharing the same name too), falling back to
/// a numeric suffix. Pre-existing files from a PRIOR run are intentionally
/// left alone to overwrite — re-running a conversion/delivery is expected to
/// replace its own prior output, only a collision WITHIN this run is the
/// failure mode being guarded against.
///
/// `ext == ""` omits the dot, producing a directory name instead of a file
/// name — same collision logic either way.
public func uniqueDestPath(dir: String, base: String, ext: String, sourcePath: String, used: inout Set<String>) -> String {
    let suffix = ext.isEmpty ? "" : ".\(ext)"
    let plain = (dir as NSString).appendingPathComponent("\(base)\(suffix)")
    guard used.contains(plain) else {
        used.insert(plain)
        return plain
    }
    let parentName = ((sourcePath as NSString).deletingLastPathComponent as NSString).lastPathComponent
    let prefixed = (dir as NSString).appendingPathComponent("\(parentName)_\(base)\(suffix)")
    guard used.contains(prefixed) else {
        used.insert(prefixed)
        return prefixed
    }
    var n = 2
    while true {
        let numbered = (dir as NSString).appendingPathComponent("\(parentName)_\(base)_\(n)\(suffix)")
        if !used.contains(numbered) {
            used.insert(numbered)
            return numbered
        }
        n += 1
    }
}
