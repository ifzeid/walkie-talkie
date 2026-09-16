import AppKit
import Combine
import Sparkle

@MainActor final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var feed: String
    @Published private(set) var started = false
    @Published private(set) var canCheck = false
    @Published private(set) var lastCheck: Date?
    @Published var message: String?
    @Published var automaticChecks: Bool { didSet { if started { controller.updater.automaticallyChecksForUpdates = automaticChecks } } }
    @Published var automaticDownloads: Bool { didSet { if started { controller.updater.automaticallyDownloadsUpdates = automaticDownloads } } }
    var showSettings: (() -> Void)?
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    private var observations = Set<AnyCancellable>()
    private let defaults: UserDefaults
    private let bundledFeed: String?
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版" }
    var hasVerificationKey: Bool {
        guard let text = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let key = Data(base64Encoded: text) else { return false }
        return key.count == 32
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bundledFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        feed = UpdateConfiguration.effectiveFeed(preference: defaults.string(forKey: UpdateConfiguration.preferenceKey), bundled: bundledFeed)
        automaticChecks = defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true
        automaticDownloads = defaults.object(forKey: "SUAutomaticallyUpdate") as? Bool ?? true
        super.init()
    }
    func startIfConfigured() {
        guard !started else { return }
        guard !feed.isEmpty else { message = "尚未连接版本发布地址。"; return }
        do {
            _ = try UpdateConfiguration.validatedFeed(feed)
            guard hasVerificationKey else { throw AppError.message("此构建缺少更新验证公钥，请重新配置发布签名。") }
            try controller.updater.start()
            started = true
            controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).sink { [weak self] in self?.canCheck = $0 }.store(in: &observations)
            controller.updater.publisher(for: \.lastUpdateCheckDate).receive(on: RunLoop.main).sink { [weak self] in self?.lastCheck = $0 }.store(in: &observations)
            message = nil
        } catch { message = error.localizedDescription }
    }
    func saveFeed(_ input: String) throws {
        if started && !controller.updater.canCheckForUpdates { throw AppError.message("正在检查或安装更新，请结束后再更改发布地址。") }
        let url = try UpdateConfiguration.validatedFeed(input)
        defaults.set(url.absoluteString, forKey: UpdateConfiguration.preferenceKey)
        feed = url.absoluteString
        if started { controller.updater.resetUpdateCycle(); message = "更新地址已保存。" } else { startIfConfigured() }
    }
    func feedURLString(for updater: SPUUpdater) -> String? { feed.isEmpty ? nil : feed }
    @objc func checkForUpdates(_ sender: Any? = nil) {
        if !started { startIfConfigured() }
        guard started else { showSettings?(); return }
        guard controller.updater.canCheckForUpdates else { return }
        controller.checkForUpdates(sender)
    }
}
