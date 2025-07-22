import FlutterMacOS
import AppKit
import NetworkExtension
import Combine
import LibXray
import SystemExtensions

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
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let status = self.packetTunnelManager?.status ?? .invalid
            let connectedDate = self.packetTunnelManager?.connectedDate ?? Date()
            let duration = Int(Date().timeIntervalSince(connectedDate))
            
            let hours = duration / 3600
            let minutes = (duration % 3600) / 60
            let seconds = duration % 60
            
            let durationString = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            
            let uploadSpeed = self.uploadSpeed
            let downloadSpeed = self.downloadSpeed
            let totalUpload = self.totalUpload
            let totalDownload = self.totalDownload
            
            let statusString: String
            switch status {
            case .connected:
                statusString = "CONNECTED"
            case .connecting:
                statusString = "CONNECTING"
            case .disconnecting:
                statusString = "DISCONNECTING"
            case .disconnected:
                statusString = "DISCONNECTED"
            case .reasserting:
                statusString = "REASSERTING"
            case .invalid:
                statusString = "INVALID"
            @unknown default:
                statusString = "UNKNOWN"
            }
            
            let statusData = [durationString, "\(uploadSpeed)", "\(downloadSpeed)", "\(totalUpload)", "\(totalDownload)", statusString]
            self.eventSink?(statusData)
        }
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
        case "testNetworkExtensionConfiguration":
            NSLog("🔧 [FlutterV2rayPlugin] Testing Network Extension configuration")
            testNetworkExtensionConfiguration(result: result)
        case "checkNetworkExtensionInstallation":
            NSLog("🔧 [FlutterV2rayPlugin] Checking Network Extension installation")
            checkNetworkExtensionInstallation(result: result)
        case "installSystemExtension":
            NSLog("🔧 [FlutterV2rayPlugin] Installing system extension")
            installSystemExtension(result: result)
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
              let _ = arguments["config"] as? String else{
            NSLog("❌ [FlutterV2rayPlugin] Invalid arguments for getServerDelay")
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for getServerDelay.", details: nil))
            return
        }
        NSLog("⏱️ [FlutterV2rayPlugin] Testing server delay for URL: \(url)")
        Task {
            // For now, return -1 since LibXrayMeasureOutboundDelay is not available
            // TODO: Implement proper delay measurement when LibXray API is available
            NSLog("⚠️ [FlutterV2rayPlugin] Delay measurement not implemented yet")
            result(-1)
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
        
        NSLog("🔧 [FlutterV2rayPlugin] Provider bundle identifier: \(providerBundleIdentifier)")
        NSLog("🔧 [FlutterV2rayPlugin] Group identifier: \(groupIdentifier)")
        
        packetTunnelManager = PacketTunnelManager(providerBundleIdentifier: providerBundleIdentifier, groupIdentifier: groupIdentifier)
        
        NSLog("✅ [FlutterV2rayPlugin] V2Ray initialized successfully")
        result(nil)
    }
    
    private func startV2Ray(call: FlutterMethodCall, result: @escaping FlutterResult) {
        NSLog("🚀 [FlutterV2rayPlugin] Starting V2Ray")
        
        guard let arguments = call.arguments as? [String: Any],
              let remark = arguments["remark"] as? String,
              let config = arguments["config"] as? String else {
            NSLog("❌ [FlutterV2rayPlugin] Invalid arguments for startV2Ray")
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for startV2Ray.", details: nil))
            return
        }
        
        NSLog("🔧 [FlutterV2rayPlugin] Remark: \(remark)")
        NSLog("🔧 [FlutterV2rayPlugin] Config length: \(config.count) characters")
        
        // Configure the packet tunnel manager
        guard let configData = config.data(using: .utf8) else {
            NSLog("❌ [FlutterV2rayPlugin] Failed to convert config to data")
            result(FlutterError(code: "CONFIG_ERROR", message: "Failed to convert config to data", details: nil))
            return
        }
        
        packetTunnelManager?.remark = remark
        packetTunnelManager?.xrayConfig = configData
        
        startTimer()
        
        Task {
            do {
                // Save VPN preferences first
                NSLog("💾 [FlutterV2rayPlugin] Saving VPN preferences")
                try await packetTunnelManager?.saveToPreferences()
                NSLog("✅ [FlutterV2rayPlugin] VPN preferences saved successfully")
                
                // Try to start the VPN - this should trigger system extension installation if needed
                NSLog("🚀 [FlutterV2rayPlugin] Starting VPN tunnel")
                try await packetTunnelManager?.start()
                NSLog("✅ [FlutterV2rayPlugin] V2Ray started successfully")
                result(nil)
                stopTimer()
            } catch {
                NSLog("❌ [FlutterV2rayPlugin] Failed to start V2Ray: \(error.localizedDescription)")
                
                // Check if the error is related to missing system extension
                let errorDescription = error.localizedDescription.lowercased()
                if errorDescription.contains("not installed") || errorDescription.contains("system extension") {
                    NSLog("🔧 [FlutterV2rayPlugin] Detected missing system extension, attempting to install...")
                    
                    // Try to install system extension manually
                    do {
                        let installResult = try await installSystemExtensionInternal()
                        NSLog("✅ [FlutterV2rayPlugin] System extension installation completed: \(installResult)")
                        
                        // Wait a moment for the system to process the installation
                        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        
                        // Try starting the VPN again after system extension installation
                        NSLog("🚀 [FlutterV2rayPlugin] Retrying VPN start after system extension installation")
                        try await packetTunnelManager?.start()
                        NSLog("✅ [FlutterV2rayPlugin] V2Ray started successfully after system extension installation")
                        result(nil)
                        stopTimer()
                        return
                    } catch let installError {
                        NSLog("❌ [FlutterV2rayPlugin] System extension installation failed: \(installError.localizedDescription)")
                        result(FlutterError(code: "SYSTEM_EXTENSION_INSTALL_FAILED",
                                          message: "Failed to install system extension: \(installError.localizedDescription)",
                                          details: nil))
                        stopTimer()
                        return
                    }
                } else {
                    result(FlutterError(code: "VPN_ERROR",
                                        message: "Failed to start VPN: \(error.localizedDescription)",
                                        details: nil))
                    stopTimer()
                    return
                }
            }
        }
    }
    
    private func installSystemExtensionInternal() async throws -> String {
        NSLog("🔧 [FlutterV2rayPlugin] Installing system extension internally")

        guard let packetTunnelManager = packetTunnelManager else {
            throw NSError(domain: "FlutterV2rayPlugin", code: 1, userInfo: [NSLocalizedDescriptionKey: "PacketTunnelManager not initialized"])
        }

        guard let providerBundleIdentifier = packetTunnelManager.providerBundleIdentifier else {
            throw NSError(domain: "FlutterV2rayPlugin", code: 2, userInfo: [NSLocalizedDescriptionKey: "Provider bundle identifier is missing"])
        }

        NSLog("🔧 [FlutterV2rayPlugin] Provider bundle identifier: \(providerBundleIdentifier)")

        // Try to trigger system extension installation by attempting to save preferences
        // This should automatically trigger the system extension installation if needed
        do {
            try await packetTunnelManager.saveToPreferences()
            NSLog("✅ [FlutterV2rayPlugin] Preferences saved successfully, system extension should be available")
            return "System extension installation triggered via preferences save"
        } catch {
            NSLog("⚠️ [FlutterV2rayPlugin] Preferences save failed, trying direct system extension installation: \(error.localizedDescription)")
            
            // Fallback to direct system extension installation
            let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: providerBundleIdentifier, queue: .main)
            request.delegate = self

            NSLog("🔧 [FlutterV2rayPlugin] Submitting direct system extension installation request...")
            
            // Submit the request
            let manager = OSSystemExtensionManager.shared
            manager.submitRequest(request)

            NSLog("✅ [FlutterV2rayPlugin] System extension installation request submitted successfully")
            return "System extension installation request submitted"
        }
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
    
    private func testNetworkExtensionConfiguration(result: @escaping FlutterResult) {
        NSLog("🔧 [FlutterV2rayPlugin] Testing Network Extension configuration")
        
        guard let packetTunnelManager = packetTunnelManager else {
            NSLog("❌ [FlutterV2rayPlugin] PacketTunnelManager not initialized")
            result(FlutterError(code: "NOT_INITIALIZED", message: "V2Ray not initialized", details: nil))
            return
        }
        
        Task {
            do {
                // Test if we can save preferences
                NSLog("🔧 [FlutterV2rayPlugin] Testing VPN preferences save")
                try await packetTunnelManager.saveToPreferences()
                NSLog("✅ [FlutterV2rayPlugin] VPN preferences save test passed")
                
                // Test if we can load the manager
                NSLog("🔧 [FlutterV2rayPlugin] Testing manager load")
                let manager = await packetTunnelManager.loadTunnelProviderManager()
                if let manager = manager {
                    NSLog("✅ [FlutterV2rayPlugin] Manager load test passed")
                    NSLog("🔧 [FlutterV2rayPlugin] Manager enabled: \(manager.isEnabled)")
                    NSLog("🔧 [FlutterV2rayPlugin] Connection status: \(manager.connection.status.rawValue)")
                } else {
                    NSLog("❌ [FlutterV2rayPlugin] Manager load test failed")
                }
                
                result("Network Extension configuration test completed")
            } catch {
                NSLog("❌ [FlutterV2rayPlugin] Network Extension test failed: \(error.localizedDescription)")
                result(FlutterError(code: "NETWORK_EXTENSION_TEST_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    private func checkNetworkExtensionInstallation(result: @escaping FlutterResult) {
        NSLog("🔧 [FlutterV2rayPlugin] Checking Network Extension installation")
        
        guard let packetTunnelManager = packetTunnelManager else {
            NSLog("❌ [FlutterV2rayPlugin] PacketTunnelManager not initialized")
            result(FlutterError(code: "NOT_INITIALIZED", message: "V2Ray not initialized", details: nil))
            return
        }
        
        Task {
            do {
                // Try to load all VPN configurations
                let managers = try await NETunnelProviderManager.loadAllFromPreferences()
                NSLog("🔧 [FlutterV2rayPlugin] Found \(managers.count) VPN configurations")
                
                for (index, manager) in managers.enumerated() {
                    NSLog("🔧 [FlutterV2rayPlugin] Configuration \(index):")
                    NSLog("  - Description: \(manager.localizedDescription ?? "nil")")
                    NSLog("  - Enabled: \(manager.isEnabled)")
                    NSLog("  - Status: \(manager.connection.status.rawValue)")
                    
                    if let protocolConfig = manager.protocolConfiguration as? NETunnelProviderProtocol {
                        NSLog("  - Provider Bundle ID: \(protocolConfig.providerBundleIdentifier ?? "nil")")
                        NSLog("  - Server Address: \(protocolConfig.serverAddress ?? "nil")")
                    }
                }
                
                // Check if our specific configuration exists
                let ourManager = managers.first { manager in
                    guard let protocolConfig = manager.protocolConfiguration as? NETunnelProviderProtocol else {
                        return false
                    }
                    return protocolConfig.providerBundleIdentifier == packetTunnelManager.providerBundleIdentifier
                }
                
                if let ourManager = ourManager {
                    NSLog("✅ [FlutterV2rayPlugin] Our Network Extension configuration found")
                    NSLog("  - Enabled: \(ourManager.isEnabled)")
                    NSLog("  - Status: \(ourManager.connection.status.rawValue)")
                } else {
                    NSLog("❌ [FlutterV2rayPlugin] Our Network Extension configuration not found")
                }
                
                result("Network Extension installation check completed")
            } catch {
                NSLog("❌ [FlutterV2rayPlugin] Error checking Network Extension installation: \(error.localizedDescription)")
                result(FlutterError(code: "NETWORK_EXTENSION_CHECK_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    private func installSystemExtension(result: @escaping FlutterResult) {
        NSLog("🔧 [FlutterV2rayPlugin] Installing system extension")

        guard let packetTunnelManager = packetTunnelManager else {
            NSLog("❌ [FlutterV2rayPlugin] PacketTunnelManager not initialized")
            result(FlutterError(code: "NOT_INITIALIZED", message: "V2Ray not initialized", details: nil))
            return
        }

        guard let providerBundleIdentifier = packetTunnelManager.providerBundleIdentifier else {
            NSLog("❌ [FlutterV2rayPlugin] Provider bundle identifier is missing")
            result(FlutterError(code: "MISSING_BUNDLE_ID", message: "Provider bundle identifier is missing", details: nil))
            return
        }

        NSLog("🔧 [FlutterV2rayPlugin] Provider bundle identifier: \(providerBundleIdentifier)")

        Task {
            // Check if system extension is already installed
            let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: providerBundleIdentifier, queue: .main)
            request.delegate = self

            NSLog("🔧 [FlutterV2rayPlugin] Submitting system extension installation request...")
            
            // Submit the request
            let manager = OSSystemExtensionManager.shared
            manager.submitRequest(request)

            NSLog("✅ [FlutterV2rayPlugin] System extension installation request submitted successfully")
            result("System extension installation request submitted")
        }
    }
}

// MARK: - OSSystemExtensionRequestDelegate
extension FlutterV2rayPlugin: OSSystemExtensionRequestDelegate {

    public func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        NSLog("🔧 [FlutterV2rayPlugin] System extension replacement requested")
        NSLog("🔧 [FlutterV2rayPlugin] Existing extension: \(existing.bundleIdentifier)")
        NSLog("🔧 [FlutterV2rayPlugin] New extension: \(ext.bundleIdentifier)")
        return .replace
    }

    public func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        NSLog("🔧 [FlutterV2rayPlugin] System extension installation needs user approval")
        NSLog("🔧 [FlutterV2rayPlugin] User should see a system dialog requesting approval")
    }

    public func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        NSLog("🔧 [FlutterV2rayPlugin] System extension installation finished with result: \(result.rawValue)")

        switch result {
        case .completed:
            NSLog("✅ [FlutterV2rayPlugin] System extension installed successfully")
        case .willCompleteAfterReboot:
            NSLog("⚠️ [FlutterV2rayPlugin] System extension will complete after reboot")
        @unknown default:
            NSLog("❓ [FlutterV2rayPlugin] System extension installation result: \(result.rawValue)")
        }
    }

    public func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        NSLog("❌ [FlutterV2rayPlugin] System extension installation failed with error: \(error.localizedDescription)")
        
        // Log additional error details
        if let nsError = error as NSError? {
            NSLog("❌ [FlutterV2rayPlugin] Error domain: \(nsError.domain)")
            NSLog("❌ [FlutterV2rayPlugin] Error code: \(nsError.code)")
            NSLog("❌ [FlutterV2rayPlugin] Error user info: \(nsError.userInfo)")
        }
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
            NSLog("❌ [PacketTunnelManager] Provider bundle identifier is missing")
            throw NSError(domain: "VPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Provider bundle identifier is missing."])
        }
        
        NSLog("🔧 [PacketTunnelManager] Saving VPN preferences")
        NSLog("🔧 [PacketTunnelManager] Provider bundle ID: \(providerBundleIdentifier)")
        NSLog("🔧 [PacketTunnelManager] Group ID: \(groupIdentifier ?? "nil")")
        NSLog("🔧 [PacketTunnelManager] Remark: \(remark)")
        NSLog("🔧 [PacketTunnelManager] Config size: \(xrayConfig.count) bytes")
        
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
            NSLog("🔧 [PacketTunnelManager] Configuration created, saving to preferences")
            try await manager.saveToPreferences()
            NSLog("✅ [PacketTunnelManager] VPN preferences saved successfully")
        } catch {
            NSLog("❌ [PacketTunnelManager] Error saving VPN preferences: \(error.localizedDescription)")
            NSLog("❌ [PacketTunnelManager] Error domain: \((error as NSError).domain), code: \((error as NSError).code)")
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
            NSLog("❌ [PacketTunnelManager] Manager not found")
            throw NSError(domain: "VPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manager not found"])
        }
        
        NSLog("🔧 [PacketTunnelManager] Manager found, checking if enabled")
        NSLog("🔧 [PacketTunnelManager] Manager enabled: \(manager.isEnabled)")
        NSLog("🔧 [PacketTunnelManager] Connection status: \(manager.connection.status.rawValue)")
        
        if !manager.isEnabled {
            NSLog("🔧 [PacketTunnelManager] Enabling manager")
            manager.isEnabled = true
            try await manager.saveToPreferences()
            NSLog("✅ [PacketTunnelManager] Manager enabled and saved")
        }
        
        do {
            NSLog("🚀 [PacketTunnelManager] Starting VPN tunnel")
            try manager.connection.startVPNTunnel()
            NSLog("✅ [PacketTunnelManager] VPN tunnel start command sent successfully")
        } catch {
            NSLog("❌ [PacketTunnelManager] Failed to start VPN tunnel: \(error.localizedDescription)")
            NSLog("❌ [PacketTunnelManager] Error domain: \((error as NSError).domain), code: \((error as NSError).code)")
            throw error
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
    
    
    func loadTunnelProviderManager() async -> NETunnelProviderManager? {
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