#!/usr/bin/env python3
"""Exercise the shipping matcher with deterministic PhotoKit callback fixtures.
This does not substitute for permission and library acceptance on a real iPhone.
"""
import os,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
source=(root/'HappyLifeParent/DearPhotoSource.swift').read_text()
matcher='private enum MomentLibraryOriginals {'+source.split('private enum MomentLibraryOriginals {',1)[1]
work=pathlib.Path(os.environ['ATLAS_BUILD_WORK'])
fixtures=r'''
import Foundation
import UniformTypeIdentifiers

enum PHAuthorizationStatus { case authorized, limited, denied }
enum PHAccessLevel { case readWrite }
final class PHPhotoLibrary {
 static var permission = PHAuthorizationStatus.authorized
 static func authorizationStatus(for level: PHAccessLevel) -> PHAuthorizationStatus { permission }
}
enum PHAssetMediaType: Int { case image = 1, video = 2 }
enum PHAssetResourceType: Int { case photo = 1, adjustmentData = 7 }
final class PHAssetResource {
 let type = PHAssetResourceType.photo
 let uniformTypeIdentifier = "public.jpeg"
 let originalFilename: String
 var bytes: Data
 let cloud: Bool
 static func assetResources(for asset: PHAsset) -> [PHAssetResource] { [asset.resource] }
 init(_ filename: String, _ bytes: Data, cloud: Bool = false) { originalFilename=filename; self.bytes=bytes; self.cloud=cloud }
}
final class PHFetchOptions { var predicate: NSPredicate?; var sortDescriptors: [NSSortDescriptor]? }
final class Assets {
 let rows: [PHAsset]; init(_ rows: [PHAsset]) { self.rows=rows }
 var count: Int { rows.count }
 func object(at index: Int) -> PHAsset { rows[index] }
}
final class PHAsset {
 static var visible: [PHAsset] = []
 let localIdentifier: String
 let modificationDate: Date? = Date(timeIntervalSince1970: 123)
 let resource: PHAssetResource
 init(_ id: String, _ resource: PHAssetResource) { localIdentifier=id; self.resource=resource }
 static func fetchAssets(with options: PHFetchOptions) -> Assets { Assets(visible) }
 static func assetResources(for asset: PHAsset) -> [PHAssetResource] { [asset.resource] }
}
typealias PHAssetResourceDataRequestID = Int32
final class PHAssetResourceRequestOptions { var isNetworkAccessAllowed = true }
final class PHAssetResourceManager: @unchecked Sendable {
 static let shared = PHAssetResourceManager()
 static func `default`() -> PHAssetResourceManager { shared }
 let lock=NSLock()
 var next: Int32 = 1
 var cancelled=Set<Int32>()
 var reads: [String:Int] = [:]
 var networkRequested=false
 var started: (() -> Void)?
 func cancelDataRequest(_ id: Int32) { lock.lock(); cancelled.insert(id); lock.unlock() }
 func requestData(for resource: PHAssetResource, options: PHAssetResourceRequestOptions?, dataReceivedHandler: @escaping (Data)->Void, completionHandler: @escaping (Error?)->Void) -> Int32 {
  lock.lock(); let id=next; next += 1; reads[resource.originalFilename,default:0] += 1
  networkRequested = networkRequested || (options?.isNetworkAccessAllowed ?? true)
  let callback=started; lock.unlock(); callback?()
  DispatchQueue.global(qos:.utility).async {
   if resource.cloud { completionHandler(NSError(domain:"PhotosFixtureCloud",code:1)); return }
   for byte in resource.bytes {
    self.lock.lock(); let stop=self.cancelled.contains(id); self.lock.unlock()
    if stop { completionHandler(CancellationError()); return }
    dataReceivedHandler(Data([byte]))
   }
   completionHandler(nil)
  }
  return id
 }
}
'''
driver=r'''
@main struct MatcherChecks {
 static func main() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("library-match-fixture-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:root) }
  let abc="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  let cloud=PHAssetResource("cloud.jpg",Data("abc".utf8),cloud:true)
  let wrong=PHAssetResource("same-name.jpg",Data("xyz".utf8))
  let tooLarge=PHAssetResource("oversized.jpg",Data(repeating:1,count:10000))
  let original=PHAssetResource("different-name.jpg",Data("abc".utf8))
  PHAsset.visible=[PHAsset("cloud",cloud),PHAsset("wrong",wrong),PHAsset("large",tooLarge),PHAsset("right",original)]
  PHPhotoLibrary.permission = .denied
  let denied=try await MomentLibraryOriginals.find(length:3,sha:abc,contentType:"image/jpeg",indexRoot:root) {_,_ in}
  precondition(denied == nil && PHAssetResourceManager.shared.reads.isEmpty)
  PHPhotoLibrary.permission = .limited
  guard let first=try await MomentLibraryOriginals.find(length:3,sha:abc,contentType:"image/jpeg",indexRoot:root,progress:{_,_ in}) else { fatalError("exact original not found") }
  let firstBytes=try Data(contentsOf:first); precondition(firstBytes==Data("abc".utf8)); try FileManager.default.removeItem(at:first)
  precondition(!PHAssetResourceManager.shared.networkRequested)
  precondition(!PHAssetResourceManager.shared.cancelled.isEmpty)
  precondition(PHAssetResourceManager.shared.reads["different-name.jpg"]==2)
  guard let second=try await MomentLibraryOriginals.find(length:3,sha:abc.uppercased(),contentType:"image/jpeg",indexRoot:root,progress:{_,_ in}) else { fatalError("cached digest not reused") }
  let secondBytes=try Data(contentsOf:second); precondition(secondBytes==Data("abc".utf8)); try FileManager.default.removeItem(at:second)
  precondition(PHAssetResourceManager.shared.reads["different-name.jpg"]==3)
  original.bytes=Data("abd".utf8)
  let changed=try await MomentLibraryOriginals.find(length:3,sha:abc,contentType:"image/jpeg",indexRoot:root) {_,_ in}
  precondition(changed == nil)
  PHAsset.visible=[PHAsset("cancel",PHAssetResource("cancel.jpg",Data(repeating:5,count:1000000)))]
  var continuation: AsyncStream<Void>.Continuation!
  let started=AsyncStream<Void> { continuation=$0 }
  PHAssetResourceManager.shared.started={ continuation.yield(()) }
  let job=Task.detached { try await MomentLibraryOriginals.find(length:1000000,sha:abc,contentType:"image/jpeg",indexRoot:root,progress:{_,_ in}) }
  for await _ in started { job.cancel(); break }
  do { _ = try await job.value; fatalError("cancellation ignored") } catch is CancellationError { }
  print("PASS: denied access performs no reads; exact-byte original matches despite a different name; wrong bytes and oversize rejected; cloud skipped without network; fingerprints reused; stale matches reverified; in-flight request cancellation")
 }
}
'''
# Keep the real shipping matcher unchanged; fixtures replace only the OS boundary.
file=work/'LibraryMatcherChecks.swift';file.write_text(fixtures+matcher+driver)
exe=work/'library-matcher-checks'
subprocess.run(['xcrun','swiftc',str(root/'HappyLifeParent/NativeModels.swift'),str(file),'-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True)
