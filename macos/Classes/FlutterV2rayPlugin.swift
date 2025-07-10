import Cocoa
import FlutterMacOS
import NetworkExtension
import LibXray

public class FlutterV2rayPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {


    private var manager: NETunnelProviderManager? // Use NETunnelProviderManager directly
    private var eventSink: FlutterEventSink?
    private var timer: Timer?
    private var providerBundleIdentifier: String?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_v2ray", binaryMessenger: registrar.messenger)
        let instance = FlutterV2rayPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        let eventChannel = FlutterEventChannel(name: "flutter_v2ray/status", binaryMessenger: registrar.messenger)
        eventChannel.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        // Start a timer to periodically fetch status from the NEPacketTunnelProvider
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sendTrafficStatsRequest()
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        self.timer?.invalidate()
        self.timer = nil
        return nil
    }

    private func sendTrafficStatsRequest() {
        guard let manager = self.manager, manager.connection.status == .connected else {
            self.eventSink?(["00:00:00", "0", "0", "0", "0", "DISCONNECTED"])
            return
        }

        guard let session = manager.connection as? NETunnelProviderSession else {
            print("Error: Not a NETunnelProviderSession")
            self.eventSink?(["00:00:00", "0", "0", "0", "0", "DISCONNECTED"])
            return
        }

        let message = "xray_traffic".data(using: .utf8)!
        do {
            try session.sendProviderMessage(message) { response in
                if let responseData = response, let trafficString = String(data: responseData, encoding: .utf8) {
                    let parts = trafficString.split(separator: ",").map { String($0) }
                    if parts.count == 2 {
                        // Assuming the provider sends total upload and download
                        let totalUpload = parts[0]
                        let totalDownload = parts[1]
                        // For simplicity, speed calculation is left to the Dart side or refined later
                        self.eventSink?(["00:00:00", "0", "0", totalUpload, totalDownload, "CONNECTED"])
                    }
                } else {
                    self.eventSink?(["00:00:00", "0", "0", "0", "0", "DISCONNECTED"])
                }
            }
        } catch {
            print("Error sending traffic stats message: \(error.localizedDescription)")
            self.eventSink?(["00:00:00", "0", "0", "0", "0", "DISCONNECTED"])
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "requestPermission":
            requestPermission(result: result)
        case "initializeV2Ray":
            initializeV2Ray(call: call, result: result)
        case "startV2Ray":
            startV2Ray(call: call, result: result)
        case "stopV2Ray":
            stopV2Ray(result: result)
        case "getCoreVersion":
            getCoreVersion(result: result)
        case "getConnectedServerDelay":
            getConnectedServerDelay(call: call, result: result)
        case "getServerDelay":
            getServerDelay(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func stopV2Ray(result: @escaping FlutterResult) {
        manager?.connection.stopVPNTunnel()
        result(nil)
    }

    private func getConnectedServerDelay(call: FlutterMethodCall, result: @escaping FlutterResult){
        guard let arguments = call.arguments as? [String: Any],
              let url = arguments["url"] as? String else{
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for getConnectedServerDelay.", details: nil))
            return
        }

        guard let manager = self.manager, manager.connection.status == .connected else {
            result(-1)
            return
        }

        guard let session = manager.connection as? NETunnelProviderSession else {
            result(-1)
            return
        }

        let message = "xray_delay\(url)".data(using: .utf8)!
        do {
            try session.sendProviderMessage(message) { response in
                if let responseData = response, let delayString = String(data: responseData, encoding: .utf8), let delay = Int(delayString) {
                    result(delay)
                } else {
                    result(-1)
                }
            }
        } catch {
            print("Error sending delay message: \(error.localizedDescription)")
            result(-1)
        }
    }

    private func getServerDelay(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let url = arguments["url"] as? String,
              let config = arguments["config"] as? String else{
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for getServerDelay.", details: nil))
            return
        }

        // This method should ideally be handled by the main app process if it doesn't require the tunnel
        // For now, we'll send it as a message to the provider if the tunnel is active
        guard let manager = self.manager, manager.connection.status == .connected else {
            // If not connected, we can try to ping directly using LibXray if it's safe to do so from the main app
            // For now, returning -1 as a placeholder
            result(-1)
            return
        }

        guard let session = manager.connection as? NETunnelProviderSession else {
            result(-1)
            return
        }

        let messageDict: [String: Any] = [
            "type": "ping",
            "url": url,
            "config": config
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: messageDict, options: []),
              let messageString = String(data: jsonData, encoding: .utf8) else {
            result(-1)
            return
        }

        do {
            try session.sendProviderMessage(messageString.data(using: .utf8)!) { response in
                if let responseData = response, let delayString = String(data: responseData, encoding: .utf8), let delay = Int(delayString) {
                    result(delay)
                } else {
                    result(-1)
                }
            }
        } catch {
            print("Error sending getServerDelay message: \(error.localizedDescription)")
            result(-1)
        }
    }

    private func initializeV2Ray(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let providerBundleIdentifier = arguments["providerBundleIdentifier"] as? String,
              let groupIdentifier = arguments["groupIdentifier"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing arguments", details: nil))
            return
        }

        // Store bundle ID for later use
        self.providerBundleIdentifier = providerBundleIdentifier

        // Load the preferences for NETunnelProviderManager
        NETunnelProviderManager.loadAllFromPreferences { [weak self] (managers, error) in
            if let error = error {
                result(FlutterError(code: "VPN_ERROR", message: "Failed to load VPN preferences: \(error.localizedDescription)", details: nil))
                return
            }

            // Find or create a new manager
            self?.manager = managers?.first(where: { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerBundleIdentifier }) ?? NETunnelProviderManager()

            // Configure the protocol
            let protocolConfig = NETunnelProviderProtocol()
            protocolConfig.providerBundleIdentifier = providerBundleIdentifier
            protocolConfig.serverAddress = "Xray"
            protocolConfig.providerConfiguration = ["groupIdentifier": groupIdentifier]

            self?.manager?.protocolConfiguration = protocolConfig
            self?.manager?.isEnabled = true

            // Save the configuration
            self?.manager?.saveToPreferences { error in
                if let error = error {
                    result(FlutterError(code: "SAVE_ERROR", message: "Save failed: \(error.localizedDescription)", details: nil))
                    return
                }

                // Reload after saving to make sure the changes take effect
                self?.manager?.loadFromPreferences { _ in
                    // Returning success
                    result(nil)
                }
            }
        }
    }


    private func startV2Ray(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let remark = arguments["remark"] as? String,
              let config = arguments["config"] as? String,
              let configData = config.data(using: .utf8) else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for startV2Ray.", details: nil))
            return
        }

        guard let manager = self.manager else {
            result(FlutterError(code: "VPN_ERROR", message: "VPN Manager not initialized.", details: nil))
            return
        }

        // Update provider configuration with new remark and config
        if let protocolConfiguration = manager.protocolConfiguration as? NETunnelProviderProtocol {
            // protocolConfiguration.localizedDescription = remark // This property is not available on NETunnelProviderProtocol
            protocolConfiguration.providerConfiguration?["xrayConfig"] = config.data(using: .utf8)
            manager.protocolConfiguration = protocolConfiguration
        }

        manager.saveToPreferences { (error) in
            if let error = error {
                result(FlutterError(code: "VPN_ERROR", message: "Failed to save VPN preferences before starting: \(error.localizedDescription)", details: nil))
                return
            }

            manager.loadFromPreferences { (error) in
                if let error = error {
                    result(FlutterError(code: "VPN_ERROR", message: "Failed to reload VPN preferences before starting: \(error.localizedDescription)", details: nil))
                    return
                }

                do {
                    try manager.connection.startVPNTunnel()
                    result(nil)
                } catch {
                    result(FlutterError(code: "VPN_ERROR", message: "Failed to start VPN tunnel: \(error.localizedDescription)", details: nil))
                }
            }
        }
    }

    private func requestPermission(result: @escaping FlutterResult) {
        guard let providerBundleIdentifier = self.providerBundleIdentifier else {
            result(FlutterError(code: "UNINITIALIZED", message: "Call initializeV2Ray first", details: nil))
            return
        }

        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            if let error = error {
                result(FlutterError(code: "LOAD_ERROR", message: "Load failed: \(error)", details: nil))
                return
            }

            if let manager = managers?.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerBundleIdentifier
            }) {
                result(manager.isEnabled)
            } else {
                result(false) // Configuration doesn't exist
            }
        }
    }

    private func getCoreVersion(result: @escaping FlutterResult) {
        guard let manager = self.manager, manager.connection.status == .connected else {
            result("Unknown")
            return
        }

        guard let session = manager.connection as? NETunnelProviderSession else {
            result("Unknown")
            return
        }

        let message = "xray_version".data(using: .utf8)!
        do {
            try session.sendProviderMessage(message) { response in
                if let responseData = response, let versionString = String(data: responseData, encoding: .utf8) {
                    result(versionString)
                } else {
                    result("Unknown")
                }
            }
        } catch {
            print("Error sending version message: \(error.localizedDescription)")
            result("Unknown")
        }
    }
}
