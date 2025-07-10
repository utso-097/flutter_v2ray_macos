import NetworkExtension
import LibXray
import Tun2SocksKit
import os

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var timer: Timer?
    private var totalUpload: Int = 0
    private var totalDownload: Int = 0
    private var uploadSpeed: Int = 0
    private var downloadSpeed: Int = 0

    override func startTunnel(options: [String : NSObject]? = nil, completionHandler: @escaping (Error?) -> Void) {
        guard let protocolConfiguration = self.protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfiguration = protocolConfiguration.providerConfiguration,
              let configData = providerConfiguration["xrayConfig"] as? Data else {
            completionHandler(NSError(domain: "PacketTunnelProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Xray configuration"]))
            return
        }

        let configString = String(decoding: configData, as: UTF8.self)
        var error: NSError? = nil
        let runRequest = LibXrayNewXrayRunRequest("", configString, &error)
        if let err = error {
            completionHandler(err)
            return
        }
        let runResult = LibXrayRunXray(runRequest)
        if !runResult.isEmpty {
            completionHandler(NSError(domain: "PacketTunnelProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to start Xray: \(runResult)"]))
            return
        }

        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "192.168.1.1")
        tunnelNetworkSettings.mtu = 9000
        tunnelNetworkSettings.ipv4Settings = {
            let ipv4Settings = NEIPv4Settings(addresses: ["192.168.1.1"], subnetMasks: ["255.255.255.0"])
            ipv4Settings.includedRoutes = [NEIPv4Route.default()]
            return ipv4Settings
        }()

        setTunnelNetworkSettings(tunnelNetworkSettings) { error in
            if let error = error {
                completionHandler(error)
                return
            }
            self.startTimer()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        LibXrayStopXray()
        stopTimer()
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        guard let messageString = String(data: messageData, encoding: .utf8) else {
            completionHandler?(nil)
            return
        }
      guard let tunnelProtocol = self.protocolConfiguration as? NETunnelProviderProtocol else {
          // Handle the case where casting fails
          completionHandler?("Error: Invalid protocol configuration".data(using: .utf8))
          return
      }

      let providerConfig = tunnelProtocol.providerConfiguration
      let configData = providerConfig?["xrayConfig"] as? Data ?? Data()

        if messageString.hasPrefix("xray_traffic") {
            let statsResult = LibXrayQueryStats("")
            if let decodedData = Data(base64Encoded: statsResult) {
                do {
                    if let json = try JSONSerialization.jsonObject(with: decodedData, options: []) as? [String: Any],
                       let value = json["value"] as? String {
                        let parts = value.split(separator: ",")
                        if parts.count == 2, let up = Int(parts[0]), let down = Int(parts[1]) {
                            self.uploadSpeed = up - self.totalUpload
                            self.downloadSpeed = down - self.totalDownload
                            self.totalUpload = up
                            self.totalDownload = down
                            completionHandler?("\(self.totalUpload),\(self.totalDownload)".data(using: .utf8))
                            return
                        }
                    }
                } catch {
                    print("Error decoding traffic JSON: \(error)")
                }
            }
            completionHandler?(nil)
        } else if messageString.hasPrefix("xray_delay") {
          let url = String(messageString.dropFirst("xray_delay".count))
          do {
              // Use the same casting approach here
              guard let tunnelProtocol = self.protocolConfiguration as? NETunnelProviderProtocol else {
                  completionHandler?("Error: Invalid protocol configuration".data(using: .utf8))
                  return
              }

              let providerConfig = tunnelProtocol.providerConfiguration
              let configData = providerConfig?["xrayConfig"] as? Data ?? Data()
              let configPath = String(decoding: configData, as: UTF8.self)

              let pingRequestDict: [String: Any] = [
                  "datDir": "",
                  "configPath": configPath,
                  "timeout": 5000,
                  "url": url,
                  "proxy": ""
              ]

              let jsonData = try JSONSerialization.data(withJSONObject: pingRequestDict, options: [])
              let base64EncodedRequest = jsonData.base64EncodedString()
              let pingResult = LibXrayPing(base64EncodedRequest)

              if let decodedData = Data(base64Encoded: pingResult) {
                  if let json = try JSONSerialization.jsonObject(with: decodedData, options: []) as? [String: Any],
                     let value = json["value"] as? Int64 {
                      completionHandler?("\(value)".data(using: .utf8))
                      return
                  }
              }
          } catch {
              // Handle JSON serialization errors
              completionHandler?("Error: \(error.localizedDescription)".data(using: .utf8))
          }
      }else if messageString.hasPrefix("xray_version") {
            let versionResult = LibXrayXrayVersion()
            if let decodedData = Data(base64Encoded: versionResult) {
                do {
                    if let json = try JSONSerialization.jsonObject(with: decodedData, options: []) as? [String: Any],
                       let value = json["value"] as? String {
                        completionHandler?(value.data(using: .utf8))
                        return
                    }
                } catch {
                    print("Error decoding version JSON: \(error)")
                }
            }
            completionHandler?(nil)
        } else {
            completionHandler?(nil)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func wake() {
    }

    private func startTimer() {
        self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { _ in
            // Traffic stats are now queried on demand via handleAppMessage
        })
    }

    private func stopTimer() {
        self.timer?.invalidate()
        self.timer = nil
        self.uploadSpeed = 0
        self.downloadSpeed = 0
        self.totalUpload = 0
        self.totalDownload = 0
    }
}
