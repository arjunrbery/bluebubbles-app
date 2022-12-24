import 'dart:convert';

import 'package:animated_size_and_fade/animated_size_and_fade.dart';
import 'package:bluebubbles/app/layouts/conversation_details/dialogs/timeframe_picker.dart';
import 'package:bluebubbles/utils/share.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/settings/dialogs/sync_dialog.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/layouts/setup/pages/sync/qr_code_scanner.dart';
import 'package:bluebubbles/app/layouts/setup/dialogs/manual_entry_dialog.dart';
import 'package:bluebubbles/models/models.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:firebase_dart/firebase_dart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:universal_html/html.dart' as html;
import 'package:universal_io/io.dart';
import 'package:version/version.dart';

class ServerManagementPanelController extends StatefulController {
  final RxnInt latency = RxnInt();
  final RxnString fetchStatus = RxnString();
  final RxnString serverVersion = RxnString();
  final RxnString macOSVersion = RxnString();
  final RxnString iCloudAccount = RxnString();
  final RxnInt serverVersionCode = RxnInt();
  final RxBool privateAPIStatus = RxBool(false);
  final RxBool helperBundleStatus = RxBool(false);
  final RxnString proxyService = RxnString();
  final RxnDouble timeSync = RxnDouble();
  final RxMap<String, dynamic> stats = RxMap({});

  // Restart trackers
  int? lastRestart;
  int? lastRestartMessages;
  int? lastRestartPrivateAPI;
  final RxBool isRestarting = false.obs;
  final RxBool isRestartingMessages = false.obs;
  final RxBool isRestartingPrivateAPI = false.obs;
  final RxDouble opacity = 1.0.obs;

  @override
  void onReady() {
    super.onReady();
    if (socket.state.value == SocketState.connected) {
      updateObx(() {
        getServerStats();
      });
    }
  }

  void getServerStats() async {
    int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await http.ping();
    int later = DateTime.now().toUtc().millisecondsSinceEpoch;
    latency.value = later - now;
    http.serverInfo().then((response) {
      macOSVersion.value = response.data['data']['os_version'];
      serverVersion.value = response.data['data']['server_version'];
      Version version = Version.parse(serverVersion.value!);
      serverVersionCode.value = version.major * 100 + version.minor * 21 + version.patch;
      privateAPIStatus.value = response.data['data']['private_api'] ?? false;
      helperBundleStatus.value = response.data['data']['helper_connected'] ?? false;
      proxyService.value = response.data['data']['proxy_service'];
      iCloudAccount.value = response.data['data']['detected_icloud'];
      timeSync.value = response.data['data']['macos_time_sync'];

      http.serverStatTotals().then((response) {
        if (response.data['status'] == 200) {
          stats.addAll(response.data['data'] ?? {});
          http.serverStatMedia().then((response) {
            if (response.data['status'] == 200) {
              stats.addAll(response.data['data'] ?? {});
            }
          });
        }
        opacity.value = 1.0;
      }).catchError((_) {
        showSnackbar("Error", "Failed to load server statistics!");
        opacity.value = 1.0;
      });
    }).catchError((_) {
      showSnackbar("Error", "Failed to load server details!");
    });
  }
}

class ServerManagementPanel extends CustomStateful<ServerManagementPanelController> {
  ServerManagementPanel({
    Key? key,
  }) : super(parentController: Get.put(ServerManagementPanelController()));

  @override
  State<ServerManagementPanel> createState() => _ServerManagementPanelState();
}

class _ServerManagementPanelState extends CustomState<ServerManagementPanel, void, ServerManagementPanelController> {
  IncrementalSyncManager? manager;

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: "Connection & Server Management",
      initialHeader: "Connection & Server Details",
      iosSubtitle: iosSubtitle,
      materialSubtitle: materialSubtitle,
      tileColor: tileColor,
      headerColor: headerColor,
      bodySlivers: [
        SliverList(
          delegate: SliverChildListDelegate(
            <Widget>[
              SettingsSection(
                backgroundColor: tileColor,
                children: [
                  Obx(() {
                    bool redact = ss.settings.redactedMode.value;
                    return Container(
                        color: tileColor,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8.0, left: 15, top: 8.0, right: 15),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: controller.opacity.value,
                            child: SelectableText.rich(
                              TextSpan(
                                  children: [
                                    const TextSpan(text: "Connection Status: "),
                                    TextSpan(text: describeEnum(socket.state.value).toUpperCase(), style: TextStyle(color: getIndicatorColor(socket.state.value))),
                                    const TextSpan(text: "\n\n"),
                                    if ((controller.serverVersionCode.value ?? 0) >= 42)
                                      const TextSpan(text: "Private API Status: "),
                                    if ((controller.serverVersionCode.value ?? 0) >= 42)
                                      TextSpan(text: controller.privateAPIStatus.value ? "ENABLED" : "DISABLED", style: TextStyle(color: getIndicatorColor(controller.privateAPIStatus.value
                                          ? SocketState.connected
                                          : SocketState.disconnected))),
                                    if ((controller.serverVersionCode.value ?? 0) >= 42)
                                      const TextSpan(text: "\n\n"),
                                    if ((controller.serverVersionCode.value ?? 0) >= 42)
                                      const TextSpan(text: "Private API Helper Bundle Status: "),
                                    if ((controller.serverVersionCode.value ?? 0) >= 42)
                                      TextSpan(text: controller.helperBundleStatus.value ? "CONNECTED" : "DISCONNECTED", style: TextStyle(color: getIndicatorColor(controller.helperBundleStatus.value
                                          ? SocketState.connected
                                          : SocketState.disconnected))),
                                    if ((controller.serverVersionCode.value ?? 0) >= 42)
                                      const TextSpan(text: "\n\n"),
                                    TextSpan(text: "Server URL: ${redact ? "Redacted" : http.originOverride ?? ss.settings.serverAddress.value}", recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        Clipboard.setData(ClipboardData(text: ss.settings.serverAddress.value));
                                        showSnackbar('Copied', "Address copied to clipboard");
                                      }),
                                    const TextSpan(text: "\n\n"),
                                    TextSpan(text: "Latency: ${redact ? "Redacted" : ("${controller.latency.value ?? "N/A"} ms")}"),
                                    const TextSpan(text: "\n\n"),
                                    TextSpan(text: "Server Version: ${redact ? "Redacted" : (controller.serverVersion.value ?? "N/A")}"),
                                    const TextSpan(text: "\n\n"),
                                    TextSpan(text: "macOS Version: ${redact ? "Redacted" : (controller.macOSVersion.value ?? "N/A")}"),
                                    if (controller.iCloudAccount.value != null)
                                      const TextSpan(text: "\n\n"),
                                    if (controller.iCloudAccount.value != null)
                                      TextSpan(text: "iCloud Account: ${redact ? "Redacted" : controller.iCloudAccount.value}"),
                                    if (controller.proxyService.value != null)
                                      const TextSpan(text: "\n\n"),
                                    if (controller.proxyService.value != null)
                                      TextSpan(text: "Proxy Service: ${controller.proxyService.value!.capitalizeFirst}"),
                                    if (controller.timeSync.value != null)
                                      const TextSpan(text: "\n\n"),
                                    if (controller.timeSync.value != null)
                                      const TextSpan(text: "Server Time Sync: "),
                                    if (controller.timeSync.value != null)
                                      TextSpan(text: "${controller.timeSync.value!.toStringAsFixed(3)}s", style: TextStyle(color: getIndicatorColor(controller.timeSync.value! < 1
                                          ? SocketState.connected
                                          : SocketState.disconnected))),
                                    const TextSpan(text: "\n\n"),
                                    const TextSpan(text: "Tap to update values...", style: TextStyle(fontStyle: FontStyle.italic)),
                                  ]
                              ),
                              onTap: () {
                                if (socket.state.value != SocketState.connected) return;
                                controller.opacity.value = 0.0;
                                controller.getServerStats();
                              },
                            ),
                          ),
                        )
                    );
                  }),
                  Obx(() => AnimatedSizeAndFade.showHide(
                    show: (controller.serverVersionCode.value ?? 0) >= 42  && controller.stats.isNotEmpty,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SettingsTile(
                          title: "Show Stats",
                          subtitle: "Show iMessage statistics",
                          backgroundColor: tileColor,
                          leading: const SettingsLeadingIcon(
                            iosIcon: CupertinoIcons.chart_bar_square,
                            materialIcon: Icons.stacked_bar_chart,
                          ),
                          onTap: () {
                            showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: context.theme.colorScheme.properSurface,
                                  content: Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0, left: 15, top: 8.0, right: 15),
                                    child: SelectableText.rich(
                                      TextSpan(
                                          children: controller.stats.entries.map((e) => TextSpan(text: "${e.key.capitalizeFirst!.replaceAll("Handles", "iMessage Numbers")}: ${e.value}${controller.stats.keys.last != e.key ? "\n\n" : ""}")).toList()
                                      ),
                                      style: context.theme.textTheme.bodyLarge,
                                    ),
                                  ),
                                  title: Text("Stats", style: context.theme.textTheme.titleLarge),
                                  actions: <Widget>[
                                    TextButton(
                                      child: Text("Dismiss", style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                  ],
                                )
                            );
                          },
                        ),
                        Container(
                          color: tileColor,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 65.0),
                            child: SettingsDivider(color: context.theme.colorScheme.surfaceVariant),
                          ),
                        )
                      ],
                    )
                  )),
                  if (!ss.fcmData.isNull)
                  SettingsTile(
                    title: "Show QR Code",
                    subtitle: "Generate QR Code to screenshot or sync other devices",
                    leading: const SettingsLeadingIcon(
                      iosIcon: CupertinoIcons.qrcode,
                      materialIcon: Icons.qr_code,
                    ),
                    onTap: () {
                      List<dynamic> json = [
                        ss.settings.guidAuthKey.value,
                        ss.settings.serverAddress.value,
                        ss.fcmData.projectID,
                        ss.fcmData.storageBucket,
                        ss.fcmData.apiKey,
                        ss.fcmData.firebaseURL,
                        ss.fcmData.clientID,
                        ss.fcmData.applicationID,
                      ];
                      String qrtext = jsonEncode(json);
                      showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: context.theme.colorScheme.properSurface,
                            content: Container(
                              height: 320,
                              width: 320,
                              child: QrImageView(
                                data: qrtext,
                                version: QrVersions.auto,
                                size: 320,
                                gapless: true,
                                backgroundColor: context.theme.colorScheme.properSurface,
                                foregroundColor: context.theme.colorScheme.properOnSurface,
                              ),
                            ),
                            title: Text("QR Code", style: context.theme.textTheme.titleLarge),
                            actions: <Widget>[
                              TextButton(
                                child: Text("Dismiss", style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                              ),
                            ],
                          )
                      );
                    },
                  ),
                ],
              ),
              SettingsHeader(
                  headerColor: headerColor,
                  tileColor: tileColor,
                  iosSubtitle: iosSubtitle,
                  materialSubtitle: materialSubtitle,
                  text: "Connection & Sync"
              ),
              SettingsSection(
                backgroundColor: tileColor,
                children: [
                  /*Obx(() {
                    if (controller.proxyService.value != null && iOS)
                      return Container(
                        decoration: BoxDecoration(
                          color: tileColor,
                        ),
                        padding: EdgeInsets.only(left: 15, top: 5),
                        child: Text("Select Proxy Service"),
                      );
                    else return SizedBox.shrink();
                  }),
                  Obx(() => controller.proxyService.value != null ? SettingsOptions<String>(
                    title: "Proxy Service",
                    options: ["Ngrok", "LocalTunnel", "Dynamic DNS"],
                    initial: controller.proxyService.value!,
                    capitalize: false,
                    textProcessing: (val) => val,
                    onChanged: (val) async {
                      String? url;
                      if (val == "Dynamic DNS") {
                        TextEditingController controller = TextEditingController();
                        await showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              actions: [
                                TextButton(
                                  child: Text("OK"),
                                  onPressed: () async {
                                    if (!controller.text.isURL) {
                                      showSnackbar("Error", "Please enter a valid URL");
                                      return;
                                    }
                                    url = controller.text;
                                    Get.back();
                                  },
                                ),
                                TextButton(
                                  child: Text("Cancel"),
                                  onPressed: () {
                                    Get.back();
                                  },
                                )
                              ],
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: controller,
                                    decoration: InputDecoration(
                                      labelText: "Server Address",
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ],
                              ),
                              title: Text("Enter Server Address"),
                            )
                        );
                        if (url == null) return;
                      }
                      var res = await socket.sendMessage("change-proxy-service", {"service": val}, (_) {});
                      if (res['status'] == 200) {
                        controller.proxyService.value = val;
                        await Future.delayed(Duration(seconds: 2));
                        await socket.refreshConnection();
                        controller.opacity.value = 0.0;
                        int now = DateTime.now().toUtc().millisecondsSinceEpoch;
                        socket.sendMessage("get-server-metadata", {}, (Map<String, dynamic> res) {
                          int later = DateTime.now().toUtc().millisecondsSinceEpoch;
                          controller.latency.value = later - now;
                          controller.macOSVersion.value = res['data']['os_version'];
                          controller.serverVersion.value = res['data']['server_version'];
                          controller.privateAPIStatus.value = res['data']['private_api'];
                          controller.helperBundleStatus.value = res['data']['helper_connected'];
                          controller.proxyService.value = res['data']['proxy_service'];
                          controller.opacity.value = 1.0;
                        });
                      }
                    },
                    backgroundColor: tileColor,
                    secondaryColor: headerColor,
                  ) : SizedBox.shrink()),
                  Obx(() => controller.proxyService.value != null && !kIsWeb ? Container(
                    color: tileColor,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 65.0),
                      child: SettingsDivider(color: context.theme.colorScheme.surfaceVariant),
                    ),
                  ) : SizedBox.shrink()),*/
                  SettingsTile(
                    title: "Re-configure with BlueBubbles Server",
                    subtitle: kIsWeb || kIsDesktop ? "Click for manual entry" : "Tap to scan QR code\nLong press for manual entry",
                    isThreeLine: kIsWeb || kIsDesktop ? false : true,
                    leading: const SettingsLeadingIcon(
                      iosIcon: CupertinoIcons.gear,
                      materialIcon: Icons.room_preferences,
                    ),
                    onLongPress: kIsWeb || kIsDesktop ? null : () {
                      showDialog(
                        context: context,
                        builder: (connectContext) => ManualEntryDialog(
                          onConnect: () {
                            Get.back();
                            socket.restartSocket();
                          },
                          onClose: () {
                            Get.back();
                          },
                        ),
                      );
                    },
                    onTap: kIsWeb || kIsDesktop ? () {
                      showDialog(
                        context: context,
                        builder: (connectContext) => ManualEntryDialog(
                          onConnect: () {
                            Get.back();
                            socket.restartSocket();
                          },
                          onClose: () {
                            Get.back();
                          },
                        ),
                      );
                    } : () async {
                      List<dynamic>? fcmData;
                      try {
                        fcmData = jsonDecode(
                          await Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (BuildContext context) {
                                return QRCodeScanner();
                              },
                            ),
                          ),
                        );
                      } catch (e) {
                        return;
                      }
                      if (fcmData != null && fcmData[0] != null && sanitizeServerAddress(address: fcmData[1]) != null) {
                        final data = FCMData(
                          projectID: fcmData[2],
                          storageBucket: fcmData[3],
                          apiKey: fcmData[4],
                          firebaseURL: fcmData[5],
                          clientID: fcmData[6],
                          applicationID: fcmData[7],
                        );
                        ss.settings.guidAuthKey.value = fcmData[0];
                        ss.settings.serverAddress.value = sanitizeServerAddress(address: fcmData[1])!;

                        ss.saveSettings();
                        ss.saveFCMData(data);
                        socket.restartSocket();
                      }
                    },
                  ),
                  if (!kIsWeb)
                    Container(
                      color: tileColor,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 65.0),
                        child: SettingsDivider(color: context.theme.colorScheme.surfaceVariant),
                      ),
                    ),
                  if (!kIsWeb)
                    Obx(() => SettingsTile(
                      title: "Manually Sync Messages",
                      subtitle: socket.state.value == SocketState.connected
                          ? "Tap to sync messages" : "Disconnected, cannot sync",
                      backgroundColor: tileColor,
                      leading: const SettingsLeadingIcon(
                        iosIcon: CupertinoIcons.arrow_2_circlepath,
                        materialIcon: Icons.sync,
                      ),
                      onTap: () async {
                        if (socket.state.value != SocketState.connected) return;
                        if (manager != null) {
                          showDialog(
                            context: context,
                            builder: (context) => SyncDialog(manager: manager!),
                          );
                        } else {
                          final date = await showTimeframePicker("How Far Back?", context, showHourPicker: false);
                          if (date == null) return;
                          try {
                            manager = IncrementalSyncManager(date.millisecondsSinceEpoch);
                            showDialog(
                              context: context,
                              builder: (context) => SyncDialog(manager: manager!),
                            );
                            await manager!.start();
                          } catch (_) {}
                          Navigator.of(context).pop();
                          manager = null;
                        }
                      }),
                    ),
                  if (!kIsWeb)
                    Container(
                      color: tileColor,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 65.0),
                        child: SettingsDivider(color: context.theme.colorScheme.surfaceVariant),
                      ),
                    ),
                  if (!kIsWeb)
                    Container(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Obx(() => SettingsSwitch(
                        initialVal: ss.settings.localhostPort.value != null,
                        title: "Detect Localhost Address",
                        subtitle: "Look up localhost address for a faster direct connection",
                        backgroundColor: tileColor,
                        onChanged: (bool val) async {
                          if (val) {
                            final TextEditingController portController = TextEditingController();
                            await showDialog(
                              context: context,
                              builder: (_) {
                                return AlertDialog(
                                  actions: [
                                    TextButton(
                                      child: Text("Cancel", style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                                      onPressed: () => Get.back(),
                                    ),
                                    TextButton(
                                      child: Text("OK", style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                                      onPressed: () async {
                                        if (portController.text.isEmpty || !portController.text.isNumericOnly) {
                                          showSnackbar("Error", "Enter a valid port!");
                                          return;
                                        }
                                        Get.back();
                                        ss.settings.localhostPort.value = portController.text;
                                      },
                                    ),
                                  ],
                                  content: TextField(
                                    controller: portController,
                                    decoration: const InputDecoration(
                                      labelText: "Port Number",
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                  title: Text("Enter Server Port", style: context.theme.textTheme.titleLarge),
                                  backgroundColor: context.theme.colorScheme.properSurface,
                                );
                              }
                            );
                          } else {
                            ss.settings.localhostPort.value = null;
                          }
                          ss.settings.save();
                          if (ss.settings.localhostPort.value == null) {
                            http.originOverride = null;
                          } else {
                            NetworkTasks.detectLocalhost(createSnackbar: true);
                          }
                        },
                      ))
                    ),
                  Container(
                    color: tileColor,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 65.0),
                      child: SettingsDivider(color: context.theme.colorScheme.surfaceVariant),
                    ),
                  ),
                  SettingsTile(
                    title: "Fetch Latest URL",
                    subtitle: "Forcefully fetch latest URL from Firebase",
                    backgroundColor: tileColor,
                    onTap: () async {
                      String? newUrl = await fdb.fetchNewUrl();
                      showSnackbar("Notice", "Fetched URL: $newUrl");
                      socket.restartSocket();
                    }),
                ]
              ),
              SettingsHeader(
                  headerColor: headerColor,
                  tileColor: tileColor,
                  iosSubtitle: iosSubtitle,
                  materialSubtitle: materialSubtitle,
                  text: "Server Actions"
              ),
              SettingsSection(
                backgroundColor: tileColor,
                children: [
                  Obx(() => SettingsTile(
                    title: "Fetch${kIsWeb || kIsDesktop ? "" : " & Share"} Server Logs",
                    subtitle: controller.fetchStatus.value ?? (socket.state.value == SocketState.connected
                        ? "Tap to fetch logs" : "Disconnected, cannot fetch logs"),
                    backgroundColor: tileColor,
                    leading: const SettingsLeadingIcon(
                      iosIcon: CupertinoIcons.doc_plaintext,
                      materialIcon: Icons.article,
                    ),
                    onTap: () {
                      if (socket.state.value != SocketState.connected) return;

                      controller.fetchStatus.value = "Fetching logs, please wait...";

                      http.serverLogs().then((response) async {
                        if (kIsDesktop) {
                          String downloadsPath = (await getDownloadsDirectory())!.path;
                          await File(join(downloadsPath, "main.log")).writeAsString(response.data['data']);
                          return showSnackbar('Success', 'Saved logs to $downloadsPath!');
                        }

                        if (kIsWeb) {
                          final bytes = utf8.encode(response.data['data']);
                          final content = base64.encode(bytes);
                          html.AnchorElement(
                              href: "data:application/octet-stream;charset=utf-16le;base64,$content")
                            ..setAttribute("download", "main.log")
                            ..click();
                          return;
                        }

                        File logFile = File("${fs.appDocDir.path}/attachments/main.log");

                        if (await logFile.exists()) {
                          await logFile.delete();
                        }

                        await logFile.writeAsString(response.data['data']);

                        try {
                          Share.file("BlueBubbles Server Log", logFile.absolute.path);
                          controller.fetchStatus.value = null;
                        } catch (ex) {
                          controller.fetchStatus.value = "Failed to share file! ${ex.toString()}";
                        }
                      }).catchError((_) {
                        controller.fetchStatus.value = "Failed to fetch logs!";
                      });
                    },
                  )),
                  Container(
                    color: tileColor,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 65.0),
                      child: SettingsDivider(color: context.theme.colorScheme.surfaceVariant),
                    ),
                  ),
                  Obx(() => SettingsTile(
                      title: "Restart iMessage",
                      subtitle: controller.isRestartingMessages.value && socket.state.value == SocketState.connected
                          ? "Restart in progress..."
                          : socket.state.value == SocketState.connected
                          ? "Restart the iMessage app"
                          : "Disconnected, cannot restart",
                      backgroundColor: tileColor,
                      leading: const SettingsLeadingIcon(
                        iosIcon: CupertinoIcons.chat_bubble,
                        materialIcon: Icons.sms,
                      ),
                      onTap: () async {
                        if (socket.state.value != SocketState.connected || controller.isRestartingMessages.value) return;

                        controller.isRestartingMessages.value = true;

                        // Prevent restarting more than once every 30 seconds
                        int now = DateTime.now().toUtc().millisecondsSinceEpoch;
                        if (controller.lastRestartMessages != null && now - controller.lastRestartMessages! < 1000 * 30) return;

                        // Save the last time we restarted
                        controller.lastRestartMessages = now;

                        // Execute the restart
                        http.restartImessage().then((_) {
                          controller.isRestartingMessages.value = false;
                        }).catchError((_) {
                          controller.isRestartingMessages.value = false;
                        });
                      },
                      trailing: Obx(() => (!controller.isRestartingMessages.value)
                          ? Icon(Icons.refresh, color: context.theme.colorScheme.outline)
                          : Container(
                          constraints: const BoxConstraints(
                            maxHeight: 20,
                            maxWidth: 20,
                          ),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.primary),
                          ))))),
                  Container(
                    color: tileColor,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 65.0),
                      child: SettingsDivider(color: context.theme.colorScheme.surfaceVariant),
                    ),
                  ),
                  Obx(() => AnimatedSizeAndFade.showHide(
                    show: ss.settings.enablePrivateAPI.value
                        && (controller.serverVersionCode.value ?? 0) >= 41,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SettingsTile(
                          title: "Restart Private API & Services",
                          subtitle: controller.isRestartingPrivateAPI.value && socket.state.value == SocketState.connected
                              ? "Restart in progress..."
                              : socket.state.value == SocketState.connected
                              ? "Restart the Private API"
                              : "Disconnected, cannot restart",
                          backgroundColor: tileColor,
                          leading: const SettingsLeadingIcon(
                            iosIcon: CupertinoIcons.exclamationmark_shield,
                            materialIcon: Icons.gpp_maybe,
                          ),
                          onTap: () async {
                            if (socket.state.value != SocketState.connected || controller.isRestartingPrivateAPI.value) return;

                            controller.isRestartingPrivateAPI.value = true;

                            // Prevent restarting more than once every 30 seconds
                            int now = DateTime.now().toUtc().millisecondsSinceEpoch;
                            if (controller.lastRestartPrivateAPI != null && now - controller.lastRestartPrivateAPI! < 1000 * 30) return;

                            // Save the last time we restarted
                            controller.lastRestartPrivateAPI = now;

                            // Execute the restart
                            http.softRestart().then((_) {
                              controller.isRestartingPrivateAPI.value = false;
                            }).catchError((_) {
                              controller.isRestartingPrivateAPI.value = false;
                            });
                          },
                          trailing: (!controller.isRestartingPrivateAPI.value)
                              ? Icon(Icons.refresh, color: context.theme.colorScheme.outline)
                              : Container(
                              constraints: const BoxConstraints(
                                maxHeight: 20,
                                maxWidth: 20,
                              ),
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.primary),
                              ))),
                        Container(
                          color: tileColor,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 65.0),
                            child: SettingsDivider(color: context.theme.colorScheme.surfaceVariant),
                          ),
                        )
                      ],
                    ),
                  )),
                  Obx(() => SettingsTile(
                      title: "Restart BlueBubbles Server",
                      subtitle: (controller.isRestarting.value)
                          ? "Restart in progress..."
                          : "This will briefly disconnect you",
                      leading: const SettingsLeadingIcon(
                        iosIcon: CupertinoIcons.desktopcomputer,
                        materialIcon: Icons.dvr,
                      ),
                      onTap: () async {
                        if (controller.isRestarting.value) return;

                        controller.isRestarting.value = true;

                        // Prevent restarting more than once every 30 seconds
                        int now = DateTime.now().toUtc().millisecondsSinceEpoch;
                        if (controller.lastRestart != null && now - controller.lastRestart! < 1000 * 30) return;

                        // Save the last time we restarted
                        controller.lastRestart = now;

                        // Perform the restart
                        try {
                          if (kIsDesktop || kIsWeb) {
                            var db = FirebaseDatabase(databaseURL: ss.fcmData.firebaseURL);
                            var ref = db.reference().child('config').child('nextRestart');
                            await ref.set(DateTime.now().toUtc().millisecondsSinceEpoch);
                          } else {
                            await mcs.invokeMethod(
                              "set-next-restart", {
                                "value": DateTime.now().toUtc().millisecondsSinceEpoch
                              }
                            );
                          }
                        } finally {
                          controller.isRestarting.value = false;
                        }
                      },
                      trailing: (!controller.isRestarting.value)
                          ? Icon(Icons.refresh, color: context.theme.colorScheme.outline)
                          : Container(
                          constraints: const BoxConstraints(
                            maxHeight: 20,
                            maxWidth: 20,
                          ),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.primary),
                          )))),
                  Obx(() => AnimatedSizeAndFade.showHide(
                    show: (controller.serverVersionCode.value ?? 0) >= 42,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          color: tileColor,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 65.0),
                            child: SettingsDivider(color: context.theme.colorScheme.surfaceVariant),
                          ),
                        ),
                        SettingsTile(
                          title: "Check for Server Updates",
                          subtitle: "Check for new BlueBubbles Server updates",
                          backgroundColor: tileColor,
                          leading: const SettingsLeadingIcon(
                            iosIcon: CupertinoIcons.desktopcomputer,
                            materialIcon: Icons.dvr,
                          ),
                          onTap: () async {
                            await ss.checkServerUpdate();
                          },
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ],
          ),
        ),
      ]
    );
  }
}
