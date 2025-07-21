import FlutterMacOS
import AppKit
import NetworkExtension
import Combine
import LibXray

public class FlutterV2rayPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    private var packetTunnelManager: PacketTunnelManager? = nil
    
    private var timer: Timer?
    private var eventSink: FlutterEventSink?
    private var totalUpload: Int = 0
    private var totalDownload: Int = 0
    private var uploadSpeed: Int = 0
    private var downloadSpeed: Int = 0
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        NSLog("🔧 [FlutterV2rayPlugin] Registering FlutterV2rayPlugin")
        
        let channel = FlutterMethodChannel(name: "flutter_v2ray", binaryMessenger: registrar.messenger)
        let instance = FlutterV2rayPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        let eventChannel = FlutterEventChannel(name: "flutter_v2ray/status", binaryMessenger: registrar.messenger)
        eventChannel.setStreamHandler(instance)
        
        NSLog("✅ [FlutterV2rayPlugin] FlutterV2rayPlugin registered successfully")
    }
    
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        NSLog("📡 [FlutterV2rayPlugin] Event stream listener started")
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        NSLog("📡 [FlutterV2rayPlugin] Event stream listener cancelled")
        self.eventSink = nil
        return nil
    }
    
    private func startTimer() {
        NSLog("⏰ [FlutterV2rayPlugin] Starting status timer")
        self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { _ in
            let elapsed = Date().timeIntervalSince(self.packetTunnelManager?.connectedDate ?? Date())
            let time = Int(elapsed)
            let seconds = time % 60
            let minutes = (time / 60) % 60
            let hours = (time / 3600)
            let duration =  String(format: "%0.2d:%0.2d:%0.2d",hours,minutes,seconds)
            self.eventSink?([duration, "\(self.uploadSpeed)", "\(self.downloadSpeed)", "\(self.totalUpload)", "\(self.totalDownload)", "CONNECTED"])
            Task{
                do{
                    let response =  try await self.packetTunnelManager?.sendProviderMessage(data: "xray_traffic".data(using: .utf8)!)
                    if response != nil{
                        let traffic = String(decoding: response!, as: UTF8.self)
                        let parts = traffic.split(separator: ",")
                        if let up = Int(parts[0]), let down = Int(parts[1]) {
                            self.uploadSpeed = up - self.totalUpload
                            self.downloadSpeed = down - self.totalDownload
                            self.totalUpload = up
                            self.totalDownload = down
                            NSLog("📊 [FlutterV2rayPlugin] Traffic updated - Upload: \(self.uploadSpeed), Download: \(self.downloadSpeed)")
                        }
                    }
                }catch{
                    NSLog("❌ [FlutterV2rayPlugin] Error in traffic: \(error.localizedDescription)")
                }
            }
        })
    }
    
    private func stopTimer() {
        NSLog("⏰ [FlutterV2rayPlugin] Stopping status timer")
        self.timer?.invalidate()
        self.timer = nil
        self.eventSink?(["00:00:00", "0", "0", "0", "0", "DISCONNECTED"])
        self.uploadSpeed = 0
        self.downloadSpeed = 0
        self.totalUpload = 0
        self.totalDownload = 0
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        NSLog("📞 [FlutterV2rayPlugin] Method called: \(call.method)")
        
        switch call.method {
        case "requestPermission":
            NSLog("🔐 [FlutterV2rayPlugin] Requesting permission")
            requestPermission(result: result)
        case "initializeV2Ray":
            NSLog("🏁 [FlutterV2rayPlugin] Initializing V2Ray")
            initializeV2Ray(call: call, result: result)
        case "startV2Ray":
            NSLog("🚀 [FlutterV2rayPlugin] Starting V2Ray")
            startV2Ray(call: call, result: result)
        case "stopV2Ray":
            NSLog("🛑 [FlutterV2rayPlugin] Stopping V2Ray")
            stopV2Ray(result: result)
        case "getCoreVersion":
            NSLog("🔧 [FlutterV2rayPlugin] Getting core version")
            getCoreVersion(result: result)
        case "getConnectedServerDelay":
            NSLog("⏱️ [FlutterV2rayPlugin] Getting connected server delay")
            getConnectedServerDelay(call: call, result: result)
        case "getServerDelay":
            NSLog("⏱️ [FlutterV2rayPlugin] Getting server delay")
            getServerDelay(call: call, result: result)
        default:
            NSLog("❌ [FlutterV2rayPlugin] Unknown method: \(call.method)")
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func stopV2Ray(result: FlutterResult) {
        NSLog("🛑 [FlutterV2rayPlugin] Stopping V2Ray tunnel")
        packetTunnelManager?.stop()
        stopTimer()
        NSLog("✅ [FlutterV2rayPlugin] V2Ray stopped successfully")
        result(nil)
    }
    
    private func getConnectedServerDelay(call: FlutterMethodCall, result: @escaping FlutterResult){
        guard let arguments = call.arguments as? [String: Any],
              let url = arguments["url"] as? String else{
            NSLog("❌ [FlutterV2rayPlugin] Invalid arguments for getConnectedServerDelay")
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for getConnectedServerDelay.", details: nil))
            return
        }
        NSLog("⏱️ [FlutterV2rayPlugin] Testing connected server delay for URL: \(url)")
        Task {
            do {
                let delay = try await packetTunnelManager?.sendProviderMessage(data: "xray_delay\(url)".data(using: .utf8)!) ?? "-1".data(using: .utf8)!
                let delayValue = Int(String(decoding: delay, as: UTF8.self))
                NSLog("⏱️ [FlutterV2rayPlugin] Connected server delay: \(delayValue ?? -1)ms")
                result(delayValue)
            }catch{
                NSLog("❌ [FlutterV2rayPlugin] Error getting connected server delay: \(error.localizedDescription)")
                result(-1)
            }
        }
    }
    
    private func getServerDelay(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let url = arguments["url"] as? String,
              let config = arguments["config"] as? String else{
            NSLog("❌ [FlutterV2rayPlugin] Invalid arguments for getServerDelay")
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for getServerDelay.", details: nil))
            return
        }
        NSLog("⏱️ [FlutterV2rayPlugin] Testing server delay for URL: \(url)")
        Task {
            // Create a ping request with the config and URL
            let pingConfig = """
            {
                "config": "\(config)",
                "url": "\(url)"
            }
            """
            
            if let base64Config = pingConfig.data(using: .utf8)?.base64EncodedString() {
                NSLog("🔧 [FlutterV2rayPlugin] Sending ping request to LibXray")
                let pingResult = LibXrayPing(base64Config)
                
                // Parse the result which should be base64 encoded JSON
                if let resultData = Data(base64Encoded: pingResult),
                   let resultString = String(data: resultData, encoding: .utf8),
                   let jsonData = resultString.data(using: .utf8) {
                    
                    do {
                        if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                           let success = json["success"] as? Bool,
                           success,
                           let data = json["data"] as? Int {
                            NSLog("⏱️ [FlutterV2rayPlugin] Server delay result: \(data)ms")
                            result(data)
                        } else {
                            NSLog("❌ [FlutterV2rayPlugin] Ping failed or returned invalid data")
                            result(-1)
                        }
                    } catch {
                        NSLog("❌ [FlutterV2rayPlugin] Error parsing ping result: \(error.localizedDescription)")
                        result(-1)
                    }
                } else {
                    NSLog("❌ [FlutterV2rayPlugin] Invalid ping result format")
                    result(-1)
                }
            } else {
                NSLog("❌ [FlutterV2rayPlugin] Failed to encode ping config")
                result(-1)
            }
        }
    }
    
    private func startV2Ray(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let remark = arguments["remark"] as? String,
              let config = arguments["config"] as? String,
              let configData = config.data(using: .utf8) else {
            NSLog("❌ [FlutterV2rayPlugin] Invalid arguments for startV2Ray")
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for startV2Ray.", details: nil))
            return
        }
        NSLog("🚀 [FlutterV2rayPlugin] Starting V2Ray with remark: \(remark)")
        NSLog("🔧 [FlutterV2rayPlugin] Config length: \(config.count) characters")
        
        packetTunnelManager?.remark = remark
        packetTunnelManager?.xrayConfig = configData
        Task {
            do {
                NSLog("💾 [FlutterV2rayPlugin] Saving VPN preferences")
                try await packetTunnelManager?.saveToPreferences()
                NSLog("🚀 [FlutterV2rayPlugin] Starting VPN tunnel")
                try await packetTunnelManager?.start()
                NSLog("✅ [FlutterV2rayPlugin] V2Ray started successfully")
                result(nil)
                return
            } catch {
                NSLog("❌  Failed to start VPN: \(error.localizedDescription)")
                result(FlutterError(code: "VPN_ERROR",
                                    message: "Failed to start VPN: \(error.localizedDescription)",
                                    details: nil))
                stopTimer()
                return
            }
        }
        startTimer()
    }
    
    private func requestPermission(result: @escaping FlutterResult) {
        NSLog("🔐 [FlutterV2rayPlugin] Requesting VPN permission")
        Task {
            let isGranted = await packetTunnelManager?.testSaveAndLoadProfile() ?? false
            NSLog("🔐 [FlutterV2rayPlugin] Permission result: \(isGranted)")
            result(isGranted)
        }
    }
    
    private func getCoreVersion(result: @escaping FlutterResult) {
        NSLog("🔧 [FlutterV2rayPlugin] Getting LibXray version")
        Task {
            let version = LibXrayXrayVersion()
            NSLog("🔧 [FlutterV2rayPlugin] LibXray version: \(version)")
            result(version)
        }
    }
    
    private func initializeV2Ray(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let providerBundleIdentifier = arguments["providerBundleIdentifier"] as? String,
              let groupIdentifier = arguments["groupIdentifier"] as? String else {
            NSLog("❌ [FlutterV2rayPlugin] Invalid arguments for initializeV2Ray")
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for initializeV2Ray.", details: nil))
            return
        }
        NSLog("🏁 [FlutterV2rayPlugin] Initializing V2Ray")
        NSLog("📦 [FlutterV2rayPlugin] Provider bundle ID: \(providerBundleIdentifier)")
        NSLog("👥 [FlutterV2rayPlugin] Group ID: \(groupIdentifier)")
        
        self.packetTunnelManager = PacketTunnelManager(providerBundleIdentifier: "\(providerBundleIdentifier).XrayTunnelMac", groupIdentifier: groupIdentifier)
        
        if self.packetTunnelManager?.status != NEVPNStatus.disconnected{
            NSLog("🔄 [FlutterV2rayPlugin] VPN is already connected, starting timer")
            startTimer()
        } else {
            NSLog("📴 [FlutterV2rayPlugin] VPN is disconnected")
        }
        NSLog("✅ [FlutterV2rayPlugin] V2Ray initialized successfully")
        result(nil)
    }
}
final class PacketTunnelManager: ObservableObject {
    var providerBundleIdentifier: String?
    var groupIdentifier: String?
    var remark: String = "Xray"
    var xrayConfig: Data = "".data(using: .utf8)!
    
    private var cancellables: Set<AnyCancellable> = []
    
    @Published private var manager: NETunnelProviderManager?
    
    @Published private(set) var isProcessing: Bool = false
    
    var status: NEVPNStatus? {
        manager.flatMap { $0.connection.status }
    }
    
    var connectedDate: Date? {
        manager.flatMap { $0.connection.connectedDate }
    }
    
    init(providerBundleIdentifier: String, groupIdentifier: String) {
        self.providerBundleIdentifier = providerBundleIdentifier
        self.groupIdentifier = groupIdentifier
        isProcessing = true
        Task(priority: .userInitiated) {
            await self.reload()
            await MainActor.run {
                self.isProcessing = false
            }
        }
    }
    
    
    func reload() async {
        self.cancellables.removeAll()
        self.manager = await self.loadTunnelProviderManager()
        NotificationCenter.default
            .publisher(for: .NEVPNConfigurationChange, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in
                Task(priority: .high) {
                    self.manager = await self.loadTunnelProviderManager()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: .NEVPNStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in objectWillChange.send() }
            .store(in: &cancellables)
    }
    
    func saveToPreferences() async throws {
        guard let providerBundleIdentifier = providerBundleIdentifier else {
            throw NSError(domain: "VPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Provider bundle identifier is missing."])
        }
        
        do {
            let manager = self.manager ?? NETunnelProviderManager()
            manager.localizedDescription = remark
            manager.protocolConfiguration = {
                let configuration = NETunnelProviderProtocol()
                configuration.providerBundleIdentifier = providerBundleIdentifier
                configuration.serverAddress = "Xray"
                configuration.providerConfiguration = [
                    "xrayConfig": xrayConfig
                ]
                if #available(iOS 14.2, *) {
                    configuration.excludeLocalNetworks = true
                } else {
                    // Fallback on earlier versions
                }
                return configuration
            }()
            manager.isEnabled = true
            try await manager.saveToPreferences()
        } catch {
            print("Error saving VPN preferences: \(error.localizedDescription)")
            throw error
        }
    }
    
    func removeFromPreferences() async throws {
        guard let manager = manager else {
            return
        }
        try await manager.removeFromPreferences()
    }
    
    func start() async throws {
        guard let manager = manager else {
            throw NSError(domain: "VPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manager not found"])
        }
        
        if !manager.isEnabled {
            manager.isEnabled = true
            try await manager.saveToPreferences()
        }
        
        do {
            // Assuming you have a manager instance of NETunnelProviderManager
            try  manager.connection.startVPNTunnel()
        } catch {
            print("Failed to start VPN tunnel: \(error.localizedDescription)")
        }
    }
    
    func stop() {
        guard let manager = manager else {
            return
        }
        manager.connection.stopVPNTunnel()
    }
    
    @discardableResult
    func sendProviderMessage(data: Data) async throws -> Data? {
        guard let manager = manager else {
            return nil
        }
        
        guard let session = manager.connection as? NETunnelProviderSession else {
            throw NSError(domain: "VPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid connection type"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(data) { response in
                    continuation.resume(with: .success(response))
                }
            } catch {
                continuation.resume(with: .failure(error))
            }
        }
    }
    
    func testSaveAndLoadProfile() async -> Bool{
        do {
            try await saveToPreferences()
            
            // Now reload the manager after saving
            let _ = await loadTunnelProviderManager()
            return true
            
        } catch {
            print("Error during save and load test: \(error.localizedDescription)")
            return false
        }
    }
    
    
    private func loadTunnelProviderManager() async -> NETunnelProviderManager? {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            
            
            guard let reval = managers.first(where: {
                guard let configuration = $0.protocolConfiguration as? NETunnelProviderProtocol else {
                    return false
                }
                return configuration.providerBundleIdentifier == providerBundleIdentifier
            }) else {
                return nil
            }
            
            try await reval.loadFromPreferences()
            return reval
        } catch {
            print("Error loading tunnel provider manager: \(error.localizedDescription)")
            return nil
        }
    }
}