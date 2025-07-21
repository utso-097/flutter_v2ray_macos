//
//  main.swift
//  XrayTunnel
//
//  Created by Md Samaul Haque Malik on 10/7/25.
//

import Foundation
import NetworkExtension

NSLog("🚀 [SystemExtension] Starting system extension...")

autoreleasepool {
    NSLog("🔧 [SystemExtension] Starting NEProvider system extension mode")
    NEProvider.startSystemExtensionMode()
    NSLog("✅ [SystemExtension] NEProvider system extension mode started")
}

NSLog("🔧 [SystemExtension] Calling dispatchMain()")
dispatchMain()
