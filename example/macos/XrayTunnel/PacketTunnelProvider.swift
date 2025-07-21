//
//  PacketTunnelProvider.swift
//  XrayTunnel
//
//  Created by Arshia Eihami on 13.11.2024.
//

import NetworkExtension
import LibXray
import Tun2SocksKit

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    private let logger2 = CustomLibXrayLogger()
    
    override func startTunnel(options: [String : NSObject]? = nil) async throws {
        NSLog("🚀 [PacketTunnelProvider] Starting tunnel...")
        
        do {
            // Log the options for debugging
            if let options = options {
                NSLog("🔧 [PacketTunnelProvider] Tunnel options: \(options)")
            }
            
            guard
                let protocolConfiguration = protocolConfiguration as? NETunnelProviderProtocol,
                let providerConfiguration = protocolConfiguration.providerConfiguration
            else {
                NSLog("❌ [PacketTunnelProvider] Failed to get protocol configuration")
                NSLog("🔧 [PacketTunnelProvider] Protocol configuration type: \(type(of: protocolConfiguration))")
                throw NSError(domain: "PacketTunnelProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get protocol configuration"])
            }
            
            NSLog("🔧 [PacketTunnelProvider] Provider configuration keys: \(providerConfiguration.keys)")
            
            guard let xrayConfig: Data = providerConfiguration["xrayConfig"] as? Data else {
                NSLog("❌ [PacketTunnelProvider] Missing Xray configuration")
                NSLog("🔧 [PacketTunnelProvider] Available keys in provider configuration: \(providerConfiguration.keys)")
                throw NSError(domain: "PacketTunnelProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing Xray configuration"])
            }
            
            guard let tunport: Int = parseConfig(jsonData: xrayConfig) else {
                NSLog("❌ [PacketTunnelProvider] Failed to parse config for tunnel port")
                throw NSError(domain: "PacketTunnelProvider", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse config for tunnel port"])
            }
            
            NSLog("🔧 [PacketTunnelProvider] Tunnel port: \(tunport)")
            NSLog("🔧 [PacketTunnelProvider] Xray config length: \(xrayConfig.count) bytes")
            
            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")
            settings.mtu = 9000
            settings.ipv4Settings = {
                let settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
                settings.includedRoutes = [NEIPv4Route.default()]
                return settings
            }()
            settings.ipv6Settings = {
                let settings = NEIPv6Settings(addresses: ["fd6e:a81b:704f:1211::1"], networkPrefixLengths: [64])
                settings.includedRoutes = [NEIPv6Route.default()]
                return settings
            }()
            settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "114.114.114.114"])
            
            NSLog("🌐 [PacketTunnelProvider] Setting tunnel network settings")
            try await self.setTunnelNetworkSettings(settings)
            NSLog("✅ [PacketTunnelProvider] Tunnel network settings applied")
            
            NSLog("🔧 [PacketTunnelProvider] Starting XRay...")
            self.startXRay(xrayConfig: xrayConfig)
            
            NSLog("🔧 [PacketTunnelProvider] Starting SOCKS5 tunnel...")
            self.startSocks5Tunnel(serverPort: tunport)
            
            NSLog("✅ [PacketTunnelProvider] Tunnel started successfully")
        } catch {
            NSLog("❌ [PacketTunnelProvider] Error starting tunnel: \(error.localizedDescription)")
            NSLog("❌ [PacketTunnelProvider] Error domain: \((error as NSError).domain), code: \((error as NSError).code)")
            throw error
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        NSLog("🛑 [PacketTunnelProvider] Stopping tunnel with reason: \(reason.rawValue)")
        stopXRay()
        Socks5Tunnel.quit()
        NSLog("✅ [PacketTunnelProvider] Tunnel stopped successfully")
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        if let message = String(data: messageData, encoding: .utf8) {
            NSLog("📨 [PacketTunnelProvider] Received app message: \(message)")
            
            if (message == "xray_traffic"){
                NSLog("📊 [PacketTunnelProvider] Requesting traffic stats")
                completionHandler?("\(Socks5Tunnel.stats.up.bytes),\(Socks5Tunnel.stats.down.bytes)".data(using: .utf8))
            }else if (message.hasPrefix("xray_delay")){
                let url = String(message[message.index(message.startIndex, offsetBy: 10)...])
                NSLog("⏱️ [PacketTunnelProvider] Testing delay for URL: \(url)")
                
                // Create a ping request with the URL
                let pingConfig = """
                {
                    "url": "\(url)"
                }
                """
                
                if let base64Config = pingConfig.data(using: .utf8)?.base64EncodedString() {
                    NSLog("🔧 [PacketTunnelProvider] Sending ping request to LibXray")
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
                                NSLog("⏱️ [PacketTunnelProvider] Delay result: \(data)ms")
                                completionHandler?("\(data)".data(using: .utf8))
                            } else {
                                NSLog("❌ [PacketTunnelProvider] Ping failed or returned invalid data")
                                completionHandler?("-1".data(using: .utf8))
                            }
                        } catch {
                            NSLog("❌ [PacketTunnelProvider] Error parsing ping result: \(error.localizedDescription)")
                            completionHandler?("-1".data(using: .utf8))
                        }
                    } else {
                        NSLog("❌ [PacketTunnelProvider] Invalid ping result format")
                        completionHandler?("-1".data(using: .utf8))
                    }
                } else {
                    NSLog("❌ [PacketTunnelProvider] Failed to encode ping config")
                    completionHandler?("-1".data(using: .utf8))
                }
            }
            else{
                NSLog("📨 [PacketTunnelProvider] Forwarding message to completion handler")
                completionHandler?(messageData)
            }
            
        }else{
            NSLog("❌ [PacketTunnelProvider] Failed to decode message data")
            completionHandler?(messageData)
        }
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        NSLog("😴 [PacketTunnelProvider] Tunnel going to sleep")
        completionHandler()
    }
    
    override func wake() {
        NSLog("🌅 [PacketTunnelProvider] Tunnel waking up")
    }
    
    private func startSocks5Tunnel(serverPort port: Int) {
        NSLog("🔧 [PacketTunnelProvider] Starting SOCKS5 tunnel on port \(port)")
        let config = """
        tunnel:
          mtu: 9000
        socks5:
          port: \(port)
          address: 127.0.0.1
          udp: 'udp'
        misc:
          task-stack-size: 20480
          connect-timeout: 5000
          read-write-timeout: 60000
          log-file: stdout
          log-level: debug
          limit-nofile: 65535
        """
        NSLog("🔧 [PacketTunnelProvider] SOCKS5 config: \(config)")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Socks5Tunnel.run(withConfig: .string(content: config))
            NSLog("🔧 [PacketTunnelProvider] SOCKS5 tunnel result: \(result)")
            NSLog("HEV_SOCKS5_TUNNEL_MAIN: \(result)")
        }
    }
    
    private func startXRay(xrayConfig: Data) {
        NSLog("🔧 [PacketTunnelProvider] Starting XRay with LibXray")
        
        // Check if LibXray is available
        NSLog("🔧 [PacketTunnelProvider] Checking LibXray availability...")
        
        var error: NSError?
        
        // Start XRay with the config data
        let configString = String(data: xrayConfig, encoding: .utf8) ?? ""
        NSLog("🔧 [PacketTunnelProvider] XRay config length: \(configString.count) characters")
        
        NSLog("🔧 [PacketTunnelProvider] Creating XRay run request...")
        let runRequest = LibXrayNewXrayRunRequest("", configString, &error)
        
        if let error = error {
            NSLog("❌ [PacketTunnelProvider] Failed to create XRay run request: \(error.localizedDescription)")
            NSLog("❌ [PacketTunnelProvider] Error domain: \(error.domain), code: \(error.code)")
            return
        }
        
        NSLog("✅ [PacketTunnelProvider] XRay run request created successfully")
        NSLog("🔧 [PacketTunnelProvider] Running XRay...")
        let runResult = LibXrayRunXray(runRequest)
        NSLog("🔧 [PacketTunnelProvider] XRay run result: \(runResult)")
        
        if runResult.contains("success") {
            NSLog("🎉 [PacketTunnelProvider] XRay started successfully")
        } else {
            NSLog("❌ [PacketTunnelProvider] Failed to start XRay: \(runResult)")
        }
    }
    
    private func stopXRay() {
        NSLog("🛑 [PacketTunnelProvider] Stopping XRay")
        LibXrayStopXray()
        let version = LibXrayXrayVersion()
        NSLog("🔧 [PacketTunnelProvider] XRay stopped. Version: \(version)")
        print("XRay stopped " + version)
    }
    
    private func parseConfig(jsonData: Data) -> Int? {
        NSLog("🔧 [PacketTunnelProvider] Parsing XRay config for tunnel port")
        do {
            if let configJSON = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
               let inbounds = configJSON["inbounds"] as? [[String: Any]] {
                for inbound in inbounds {
                    if let protocolType = inbound["protocol"] as? String, let port = inbound["port"] as? Int {
                        NSLog("🔧 [PacketTunnelProvider] Found inbound: \(protocolType) on port \(port)")
                        switch protocolType {
                        case "socks":
                            NSLog("✅ [PacketTunnelProvider] Using SOCKS port: \(port)")
                            return port
                        case "http":
                            NSLog("✅ [PacketTunnelProvider] Using HTTP port: \(port)")
                            return port
                        default:
                            NSLog("🔧 [PacketTunnelProvider] Skipping protocol: \(protocolType)")
                            break
                        }
                    }
                }
            }
        } catch {
            NSLog("❌ [PacketTunnelProvider] Failed to parse JSON: \(error)")
        }
        NSLog("❌ [PacketTunnelProvider] No suitable tunnel port found")
        return nil;
    }
}


class CustomLibXrayLogger: NSObject {
    
    func log(_ logMessage: String) {
        NSLog("📝 [LibXrayLogger] LibXray Log: \(logMessage)")
        print("LibXray Log: \(logMessage)")
    }
}
