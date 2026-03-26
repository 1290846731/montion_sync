import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private let channelName = "com.mj.stravasync/fitfile"
  private var channel: FlutterMethodChannel?
  private var pendingPaths: [String] = []

  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)
      channel?.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        if call.method == "getInitialOpenedFiles" {
          let paths = self.pendingPaths
          self.pendingPaths.removeAll()
          result(paths)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      if !pendingPaths.isEmpty {
        let paths = pendingPaths
        pendingPaths.removeAll()
        for p in paths {
          channel?.invokeMethod("fileOpened", arguments: p)
        }
      }
    }
    if let urlContext = connectionOptions.urlContexts.first {
      handleUrl(urlContext.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if let url = URLContexts.first?.url {
      handleUrl(url)
    }
  }

  private func handleUrl(_ url: URL) {
    var path: String?
    if url.isFileURL {
      var started = false
      if url.startAccessingSecurityScopedResource() {
        started = true
      }
      path = url.path
      if started {
        url.stopAccessingSecurityScopedResource()
      }
    } else {
      path = url.path
    }
    guard let p = path, !p.isEmpty else { return }
    if let ch = channel {
      ch.invokeMethod("fileOpened", arguments: p)
    } else {
      pendingPaths.append(p)
    }
  }
}
