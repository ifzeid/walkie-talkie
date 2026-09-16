import Foundation

struct UpdateConfiguration {
    static let preferenceKey = "WalkieTalkieUpdateFeedURL"
    static func validatedFeed(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.query == nil else {
            throw AppError.message("请填写公开的 HTTPS appcast.xml 地址，不要包含账号、密码或查询参数。")
        }
        return url
    }
    static func effectiveFeed(preference: String?, bundled: String?) -> String {
        let override = preference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? (bundled ?? "") : override
    }
}
