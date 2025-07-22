import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'dart:developer' as developer;

void main() {
  developer.log('🚀 Flutter V2Ray App Starting...', name: 'V2RayApp');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    developer.log('📱 Building MyApp widget', name: 'V2RayApp');
    return MaterialApp(
      title: 'Flutter V2Ray',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const Scaffold(
        body: HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var v2rayStatus = ValueNotifier<V2RayStatus>(V2RayStatus());
  late final FlutterV2ray flutterV2ray = FlutterV2ray(
    onStatusChanged: (status) {
      developer.log('📊 Status Changed: ${status.state}', name: 'V2RayApp');
      developer.log('📊 Duration: ${status.duration}', name: 'V2RayApp');
      developer.log('📊 Upload Speed: ${status.uploadSpeed}', name: 'V2RayApp');
      developer.log('📊 Download Speed: ${status.downloadSpeed}', name: 'V2RayApp');
      v2rayStatus.value = status;
    },
  );
  final config = TextEditingController(text: "{}");
  bool proxyOnly = false;
  final bypassSubnetController = TextEditingController();
  List<String> bypassSubnets = [];
  String? coreVersion;

  String remark = "Default Remark";

  void connect() async {
    developer.log('🔌 Attempting to connect...', name: 'V2RayApp');
    developer.log('🔌 Config: ${config.text}', name: 'V2RayApp');
    developer.log('🔌 Proxy Only: $proxyOnly', name: 'V2RayApp');
    developer.log('🔌 Bypass Subnets: $bypassSubnets', name: 'V2RayApp');
    
    if (await flutterV2ray.requestPermission()) {
      developer.log('✅ Permission granted, starting V2Ray...', name: 'V2RayApp');
      flutterV2ray.startV2Ray(
        remark: remark,
        config: config.text,
        proxyOnly: proxyOnly,
        bypassSubnets: bypassSubnets,
        notificationDisconnectButtonName: "DISCONNECT",
      );
      developer.log('✅ V2Ray start command sent', name: 'V2RayApp');
    } else {
      developer.log('❌ Permission denied', name: 'V2RayApp');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission Denied'),
          ),
        );
      }
    }
  }

  void importConfig() async {
    developer.log('📋 Attempting to import config from clipboard...', name: 'V2RayApp');
    if (await Clipboard.hasStrings()) {
      try {
        final String link =
            (await Clipboard.getData('text/plain'))?.text?.trim() ?? '';
        developer.log('📋 Clipboard content: $link', name: 'V2RayApp');
        final V2RayURL v2rayURL = FlutterV2ray.parseFromURL(link);
        remark = v2rayURL.remark;
        config.text = v2rayURL.getFullConfiguration();
        developer.log('✅ Config imported successfully', name: 'V2RayApp');
        developer.log('✅ Remark: $remark', name: 'V2RayApp');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Success',
              ),
            ),
          );
        }
      } catch (error) {
        developer.log('❌ Error importing config: $error', name: 'V2RayApp');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error: $error',
              ),
            ),
          );
        }
      }
    } else {
      developer.log('❌ No text in clipboard', name: 'V2RayApp');
    }
  }

  void delay() async {
    developer.log('⏱️ Testing server delay...', name: 'V2RayApp');
    late int delay;
    if (v2rayStatus.value.state == 'CONNECTED') {
      developer.log('⏱️ Testing connected server delay', name: 'V2RayApp');
      delay = await flutterV2ray.getConnectedServerDelay();
    } else {
      developer.log('⏱️ Testing server delay with config', name: 'V2RayApp');
      delay = await flutterV2ray.getServerDelay(config: config.text);
    }
    developer.log('⏱️ Delay result: ${delay}ms', name: 'V2RayApp');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${delay}ms',
        ),
      ),
    );
  }

  void bypassSubnet() {
    developer.log('🌐 Opening bypass subnet dialog', name: 'V2RayApp');
    bypassSubnetController.text = bypassSubnets.join("\n");
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Subnets:',
                style: TextStyle(
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 5),
              TextFormField(
                controller: bypassSubnetController,
                maxLines: 5,
                minLines: 5,
              ),
              const SizedBox(height: 5),
              ElevatedButton(
                onPressed: () {
                  bypassSubnets =
                      bypassSubnetController.text.trim().split('\n');
                  if (bypassSubnets.first.isEmpty) {
                    bypassSubnets = [];
                  }
                  developer.log('🌐 Bypass subnets updated: $bypassSubnets', name: 'V2RayApp');
                  Navigator.of(context).pop();
                },
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    developer.log('🏁 HomePage initState called', name: 'V2RayApp');
    flutterV2ray
        .initializeV2Ray(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
      providerBundleIdentifier: "com.nagorik.v2rayMobile",
      groupIdentifier: "group.com.nagorik.v2rayMobile",
    )
        .then((value) async {
      developer.log('✅ V2Ray initialized successfully', name: 'V2RayApp');
      coreVersion = await flutterV2ray.getCoreVersion();
      developer.log('🔧 Core version: $coreVersion', name: 'V2RayApp');
      setState(() {});
    }).catchError((error) {
      developer.log('❌ Error initializing V2Ray: $error', name: 'V2RayApp');
    });
  }

  @override
  void dispose() {
    developer.log('🗑️ HomePage disposing', name: 'V2RayApp');
    config.dispose();
    bypassSubnetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    developer.log('🏗️ Building HomePage widget', name: 'V2RayApp');
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 5),
            const Text(
              'V2Ray Config (json):',
              style: TextStyle(
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 5),
            TextFormField(
              controller: config,
              maxLines: 10,
              minLines: 10,
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder(
              valueListenable: v2rayStatus,
              builder: (context, value, child) {
                return Column(
                  children: [
                    Text(value.state),
                    const SizedBox(height: 10),
                    Text(value.duration),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Speed:'),
                        const SizedBox(width: 10),
                        Text(value.uploadSpeed.toString()),
                        const Text('↑'),
                        const SizedBox(width: 10),
                        Text(value.downloadSpeed.toString()),
                        const Text('↓'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Traffic:'),
                        const SizedBox(width: 10),
                        Text(value.upload.toString()),
                        const Text('↑'),
                        const SizedBox(width: 10),
                        Text(value.download.toString()),
                        const Text('↓'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('Core Version: $coreVersion'),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.all(5.0),
              child: Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      developer.log('🔐 Requesting permission...', name: 'V2RayApp');
                      final result = await flutterV2ray.requestPermission();
                      developer.log('🔐 Permission result: $result', name: 'V2RayApp');
                    },
                    child: const Text('Request Permission'),
                  ),
                  ElevatedButton(
                    onPressed: connect,
                    child: const Text('Connect'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      developer.log('🛑 Stopping V2Ray...', name: 'V2RayApp');
                      flutterV2ray.stopV2Ray();
                      developer.log('🛑 V2Ray stop command sent', name: 'V2RayApp');
                    },
                    child: const Text('Disconnect'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => proxyOnly = !proxyOnly);
                      developer.log('🔄 Proxy only mode: $proxyOnly', name: 'V2RayApp');
                    },
                    child: Text(proxyOnly ? 'Proxy Only' : 'VPN Mode'),
                  ),
                  ElevatedButton(
                    onPressed: importConfig,
                    child: const Text(
                      'Import from v2ray share link (clipboard)',
                    ),
                  ),
                  ElevatedButton(
                    onPressed: delay,
                    child: const Text('Server Delay'),
                  ),
                  ElevatedButton(
                    onPressed: bypassSubnet,
                    child: const Text('Bypass Subnet'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      developer.log('🔧 Testing Network Extension configuration...', name: 'V2RayApp');
                      try {
                        final result = await flutterV2ray.testNetworkExtensionConfiguration();
                        developer.log('✅ Network Extension test result: $result', name: 'V2RayApp');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Network Extension Test: $result')),
                          );
                        }
                      } catch (error) {
                        developer.log('❌ Network Extension test failed: $error', name: 'V2RayApp');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Network Extension Test Failed: $error')),
                          );
                        }
                      }
                    },
                    child: const Text('Test Network Extension'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      developer.log('🔧 Checking Network Extension installation...', name: 'V2RayApp');
                      try {
                        final result = await flutterV2ray.checkNetworkExtensionInstallation();
                        developer.log('✅ Network Extension installation check: $result', name: 'V2RayApp');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Network Extension Check: $result')),
                          );
                        }
                      } catch (error) {
                        developer.log('❌ Network Extension installation check failed: $error', name: 'V2RayApp');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Network Extension Check Failed: $error')),
                          );
                        }
                      }
                    },
                    child: const Text('Check Network Extension'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
