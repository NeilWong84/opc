import Flutter
import UIKit
import QuickLook
import PDFKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, QLPreviewControllerDataSource, UIDocumentPickerDelegate {
  private var referenceChannel: FlutterMethodChannel?
  private var expectedSizes: [String: Int] = [:]
  private var previewURL: URL?
  private var exportResult: FlutterResult?
  private var exportHandle: String?
  private var exportName: String?
  private var pdfDocuments: [String: PDFDocument] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let documents = FlutterMethodChannel(name: "opc/document_preview", binaryMessenger: controller.binaryMessenger)
      documents.setMethodCallHandler { [weak self] call, result in
        guard let self = self, let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "document_preview_failed", message: "Document unavailable", details: nil)); return
        }
        switch call.method {
        case "open":
          guard let bytes = args["bytes"] as? FlutterStandardTypedData,
                bytes.data.count <= 50 * 1024 * 1024,
                let document = PDFDocument(data: bytes.data), !document.isLocked,
                document.pageCount > 0, document.pageCount <= 5000 else {
            result(FlutterError(code: "document_preview_failed", message: "Document cannot be rendered", details: nil)); return
          }
          let handle = UUID().uuidString
          self.pdfDocuments[handle] = document
          result(["handle": handle, "pages": document.pageCount])
        case "page":
          guard let handle = args["handle"] as? String, let document = self.pdfDocuments[handle],
                let index = args["page"] as? Int, index >= 0, index < document.pageCount,
                let page = document.page(at: index) else {
            result(FlutterError(code: "document_preview_failed", message: "Page unavailable", details: nil)); return
          }
          let bounds = page.bounds(for: .mediaBox)
          let width = min(2000, max(320, args["width"] as? Int ?? 1600))
          let height = min(4000.0, max(1.0, Double(width) * bounds.height / max(1, bounds.width)))
          guard let png = page.thumbnail(of: CGSize(width: Double(width), height: height), for: .mediaBox).pngData() else {
            result(FlutterError(code: "document_preview_failed", message: "Page unavailable", details: nil)); return
          }
          result(FlutterStandardTypedData(bytes: png))
        case "close":
          if let handle = args["handle"] as? String { self.pdfDocuments.removeValue(forKey: handle) }
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }
      let channel = FlutterMethodChannel(name: "opc/reference_files", binaryMessenger: controller.binaryMessenger)
      referenceChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "reference_unavailable", message: "Application unavailable", details: nil))
          return
        }
        do { try self.handleReference(call, result: result) }
        catch { result(FlutterError(code: "reference_file_error", message: error.localizedDescription, details: nil)) }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func fileError(_ message: String) -> NSError {
    NSError(domain: "OPCReferenceFile", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  private func directory() throws -> URL {
    let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let directory = base.appendingPathComponent("reference_downloads", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var excluded = directory
    try excluded.setResourceValues(values)
    return directory
  }

  private func safeName(_ name: String) throws -> String {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
          !name.unicodeScalars.contains(where: { $0.value < 32 }) else {
      throw fileError("Invalid filename")
    }
    return String(name.prefix(160)).replacingOccurrences(of: ":", with: "_")
  }

  private func file(_ handle: String, partial: Bool = false) throws -> URL {
    guard handle.count > 37, UUID(uuidString: String(handle.prefix(36))) != nil,
          handle[handle.index(handle.startIndex, offsetBy: 36)] == "_",
          !handle.contains("/"), !handle.contains("\\"), !handle.hasSuffix(".part") else {
      throw fileError("Invalid file handle")
    }
    let base = try directory().standardizedFileURL
    let result = base.appendingPathComponent(handle + (partial ? ".part" : "")).standardizedFileURL
    guard result.deletingLastPathComponent() == base else { throw fileError("Invalid file path") }
    return result
  }

  private func authorize(_ handle: String, result: @escaping FlutterResult, action: @escaping () throws -> Void) {
    referenceChannel?.invokeMethod("authorize", arguments: handle) { value in
      guard let allowed = value as? Bool, allowed else {
        result(FlutterError(code: "reference_access_denied", message: "Reference access has changed", details: nil))
        return
      }
      do { try action() }
      catch { result(FlutterError(code: "reference_file_error", message: error.localizedDescription, details: nil)) }
    }
  }

  private func presenter() throws -> UIViewController {
    guard var controller = window?.rootViewController else { throw fileError("No presentation window") }
    while let presented = controller.presentedViewController { controller = presented }
    return controller
  }

  private func existingFile(_ handle: String) throws -> URL {
    let url = try file(handle)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else { throw fileError("Reference file is empty") }
    return url
  }

  private func handleReference(_ call: FlutterMethodCall, result: @escaping FlutterResult) throws {
    let args = call.arguments as? [String: Any] ?? [:]
    let handle = args["handle"] as? String ?? ""
    switch call.method {
    case "begin":
      let name = try safeName(args["fileName"] as? String ?? "")
      let size = (args["totalBytes"] as? NSNumber)?.intValue ?? 0
      guard size > 0 && size <= 100_000_000 else { throw fileError("Invalid reference size") }
      let newHandle = UUID().uuidString.lowercased() + "_" + name
      let url = try file(newHandle, partial: true)
      guard FileManager.default.createFile(atPath: url.path, contents: Data()) else { throw fileError("Could not create reference file") }
      expectedSizes[newHandle] = size
      result(newHandle)
    case "append":
      guard let bytes = args["bytes"] as? FlutterStandardTypedData, let size = expectedSizes[handle] else {
        throw fileError("Unknown reference write")
      }
      let url = try file(handle, partial: true)
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      let current = (attributes[.size] as? NSNumber)?.intValue ?? 0
      guard current + bytes.data.count <= size else { throw fileError("Unexpected byte count") }
      let output = try FileHandle(forWritingTo: url)
      defer { output.closeFile() }
      output.seekToEndOfFile()
      output.write(bytes.data)
      result(nil)
    case "finish":
      let total = (args["totalBytes"] as? NSNumber)?.intValue ?? 0
      let source = try file(handle, partial: true)
      let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
      guard expectedSizes[handle] == total, (attributes[.size] as? NSNumber)?.intValue == total else {
        throw fileError("Incomplete reference file")
      }
      let output = try FileHandle(forWritingTo: source)
      output.synchronizeFile()
      output.closeFile()
      try FileManager.default.moveItem(at: source, to: file(handle))
      expectedSizes.removeValue(forKey: handle)
      result(nil)
    case "remove":
      for partial in [false, true] {
        let url = try file(handle, partial: partial)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
      }
      expectedSizes.removeValue(forKey: handle)
      result(nil)
    case "open":
      authorize(handle, result: result) {
        self.previewURL = try self.existingFile(handle)
        let controller = QLPreviewController()
        controller.dataSource = self
        try self.presenter().present(controller, animated: true) { result(true) }
      }
    case "export":
      guard exportResult == nil else { throw fileError("An export chooser is already open") }
      let name = try safeName(args["fileName"] as? String ?? "")
      authorize(handle, result: result) {
        _ = try self.existingFile(handle)
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
          picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        } else {
          picker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
        }
        picker.delegate = self
        let presenter = try self.presenter()
        self.exportHandle = handle
        self.exportName = name
        self.exportResult = result
        presenter.present(picker, animated: true)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    previewURL! as NSURL
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = exportResult, let handle = exportHandle, let name = exportName else { return }
    exportResult = nil
    exportHandle = nil
    exportName = nil
    guard let folder = urls.first else { result(false); return }
    // A folder picker performs no copy itself. Reauthorize after the user has
    // chosen a location, immediately before reading and exporting private bytes.
    authorize(handle, result: result) {
      guard folder.startAccessingSecurityScopedResource() else { throw self.fileError("Folder access is unavailable") }
      defer { folder.stopAccessingSecurityScopedResource() }
      let source = try self.existingFile(handle)
      let manager = FileManager.default
      var target = folder.appendingPathComponent(name)
      let stem = (name as NSString).deletingPathExtension
      let suffix = (name as NSString).pathExtension
      var count = 2
      while manager.fileExists(atPath: target.path) {
        let candidate = "\(stem) (\(count))" + (suffix.isEmpty ? "" : ".\(suffix)")
        target = folder.appendingPathComponent(candidate)
        count += 1
      }
      let partial = folder.appendingPathComponent(".opc-\(UUID().uuidString).part")
      do {
        try manager.copyItem(at: source, to: partial)
        try manager.moveItem(at: partial, to: target)
      } catch {
        try? manager.removeItem(at: partial)
        throw error
      }
      result(true)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    exportResult?(false)
    exportResult = nil
    exportHandle = nil
    exportName = nil
  }
}
