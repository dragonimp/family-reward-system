#!/usr/bin/env python3
"""Compile shipping local resolver + PhotoKit matcher against deterministic OS fixtures."""
import ast, os, pathlib, subprocess
root = pathlib.Path(__file__).resolve().parents[1]
shipping = (root/'HappyLifeParent/DearPhotoSource.swift').read_text()
fixture_ast = ast.parse((root/'Tests/check-library-originals.py').read_text())
fixtures = next(ast.literal_eval(n.value) for n in fixture_ast.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'fixtures' for t in n.targets))
fixtures = fixtures.replace('case authorized, limited, denied', 'case authorized, limited, denied, notDetermined')
fixtures = fixtures.replace(' static func authorizationStatus', ' static func requestAuthorization(for level: PHAccessLevel) async -> PHAuthorizationStatus { permission }\n static func authorizationStatus')
fixtures = fixtures.replace(' let uniformTypeIdentifier = "public.jpeg"', ' var uniformTypeIdentifier = "public.jpeg"')
model = shipping[shipping.index('    private struct SharedPhoto:'):shipping.index('    weak var store:')].replace('private struct', 'struct')
methods = shipping[shipping.index('    func isSourceDevice('):shipping.index('    func recoverAllMyOriginals(')]
download = shipping[shipping.index('    func downloadOriginal('):shipping.index('        guard let store, store.identity.isAuthenticated', shipping.index('    func downloadOriginal('))]
matcher = 'private enum MomentLibraryOriginals {' + shipping.split('private enum MomentLibraryOriginals {', 1)[1]
wrapper = r'''
import CryptoKit
struct DearRecord {
 let data: [String: Any]
 var id: String { text("id") }
 func text(_ key: String) -> String { data[key] as? String ?? "" }
}
@MainActor final class LocalSource {
'''+model+r'''
 var generation = UUID()
 var currentDeviceID: String? = "4622956B-B1FC-4255-8B55-17E02680CCF5"
 var subjectCache: String? = "fixture-"+UUID().uuidString
 var localReads: [String: Task<URL?, Never>] = [:]
 var legacyLibraryAttempts = Set<String>()
 var legacyRead: Task<URL?, Error>?
 var index = Index()
 var networkRequests = 0
 let root: URL
 init(_ root: URL) { self.root = root }
 func currentSubject() async throws -> String { subjectCache! }
 func directory(for subject: String) throws -> URL { root }
 func readIndex(at root: URL) throws -> Index { index }
 func writeIndex(_ value: Index, at root: URL) throws { index=value }
 func verifiedOriginal(_ url: URL, length: Int, sha: String, subject: String) async -> Bool {
  await OriginalFileVerifier(directory: root).verify(url, length:length, sha256:sha)
 }
 func hashFile(_ url: URL) async throws -> String { SHA256.hash(data:try Data(contentsOf:url)).map {String(format:"%02x",$0)}.joined() }
'''+methods+download+r'''
        networkRequests += 1
        return URL(fileURLWithPath:"/network-fixture")
    }
}
'''
driver = r'''
@main struct LocalChecks {
 @MainActor static func main() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("local-original-tests-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:root) }
  let source=LocalSource(root)
  let tenant=UUID().uuidString, activity=UUID().uuidString
  let abc="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  func record(_ id: String, type: String="image/jpeg", local: Bool=true) -> DearRecord {
   DearRecord(data:["id":id,"sourceSubject":source.subjectCache!,"sourceDeviceId":local ? source.currentDeviceID!.lowercased() : UUID().uuidString,"length":3,"thumbnailRevision":abc,"contentType":type,"originalFileName":type.hasPrefix("video/") ? "IMG_1.MOV":"IMG_1.JPG"])
  }
  let image=PHAssetResource("IMG_1.JPG",Data("abc".utf8))
  let video=PHAssetResource("IMG_1.MOV",Data("abc".utf8));video.uniformTypeIdentifier="com.apple.quicktime-movie"
  PHAsset.visible=[PHAsset("image-id",image),PHAsset("video-id",video)]
  PHPhotoLibrary.permission = .limited
  let id=UUID().uuidString, photo=record(id)
  source.index.photos=[.init(id:id,spaceID:tenant,activityID:activity,fileName:"missing.jpg",length:3,sha256:abc,assetIdentifier:"image-id")]
  let local=await source.availableOriginal(photo:photo,spaceID:tenant.lowercased(),activityID:activity.lowercased())
  precondition(local != nil && PHAsset.fullFetches==0)
  precondition(source.index.photos.first?.assetIdentifier=="image-id")
  let received=try await source.downloadOriginal(photoID:id,spaceID:tenant,activityID:activity,record:photo)
  precondition(received==local && source.networkRequests==0)
  let movieID=UUID().uuidString, movie=record(movieID,type:"video/quicktime")
  source.index.photos.append(.init(id:movieID,spaceID:tenant,activityID:activity,fileName:"gone.mov",length:3,sha256:abc,assetIdentifier:"video-id"))
  let movieURL=await source.availableOriginal(photo:movie,spaceID:tenant,activityID:activity)
  precondition(movieURL != nil && movieURL!.pathExtension=="mov" && PHAsset.fullFetches==0)
  PHPhotoLibrary.permission = .denied
  let missing=record(UUID().uuidString)
  do { _=try await source.downloadOriginal(photoID:missing.id,spaceID:tenant,activityID:activity,record:missing);fatalError("self download was allowed") } catch { }
  precondition(source.networkRequests==0 && PHAsset.fullFetches==0)
  PHPhotoLibrary.permission = .authorized
  let other=record(UUID().uuidString,local:false)
  let otherLocal=await source.availableOriginal(photo:other,spaceID:tenant,activityID:activity)
  precondition(otherLocal==nil && PHAsset.fullFetches==0)
  let old=record(UUID().uuidString)
  let restored=await source.availableOriginal(photo:old,spaceID:tenant,activityID:activity)
  precondition(restored != nil && PHAsset.fullFetches==1)
  precondition(source.index.photos.first(where:{$0.id==old.id})?.assetIdentifier=="image-id")
  try FileManager.default.removeItem(at:restored!)
  let again=await source.availableOriginal(photo:old,spaceID:tenant,activityID:activity)
  precondition(again != nil && PHAsset.fullFetches==1)
  image.bytes=Data("xyz".utf8)
  try FileManager.default.removeItem(at:again!)
  let altered=await source.availableOriginal(photo:old,spaceID:tenant,activityID:activity)
  precondition(altered==nil && PHAsset.fullFetches==1)
  precondition(!PHAssetResourceManager.shared.networkRequested)
  print("PASS: photo/video direct asset lookup; missing copy restored locally; original filename ID persisted; UUID case; no self download; denied and other-device isolation; legacy automatic index then no rescan; changed bytes rejected; no iCloud network")
 }
}
'''
work=pathlib.Path(os.environ['ATLAS_BUILD_WORK'])
file=work/'LocalOriginalChecks.swift'; file.write_text(fixtures+wrapper+matcher+driver)
exe=work/'local-original-checks'
subprocess.run(['xcrun','swiftc',str(root/'HappyLifeParent/NativeModels.swift'),str(file),'-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True)
