// Checks GitHub Releases for a newer version (ported from ../../../src/utils/updateCheck.ts).

import Foundation

enum UpdateCheck {
    static let githubRepo = "AHRI2nd/Glyphline"

    private static func parseSemver(_ v: String) -> (Int, Int, Int) {
        let parts = v.hasPrefix("v") ? String(v.dropFirst()) : v
        let nums = parts.split(separator: ".").map { Int($0) ?? 0 }
        return (nums.count > 0 ? nums[0] : 0, nums.count > 1 ? nums[1] : 0, nums.count > 2 ? nums[2] : 0)
    }

    private static func isNewer(_ a: String, than b: String) -> Bool {
        let (aMaj, aMin, aPat) = parseSemver(a)
        let (bMaj, bMin, bPat) = parseSemver(b)
        if aMaj != bMaj { return aMaj > bMaj }
        if aMin != bMin { return aMin > bMin }
        return aPat > bPat
    }

    /// Returns the newer tag_name if one exists on GitHub, otherwise nil.
    static func checkForUpdate() async -> String? {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let latest = json["tag_name"] as? String, !latest.isEmpty else { return nil }
            return isNewer(latest, than: current) ? latest : nil
        } catch {
            return nil
        }
    }
}
