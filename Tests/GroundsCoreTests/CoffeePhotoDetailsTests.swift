import XCTest
@testable import GroundsCore

final class CoffeePhotoDetailsTests: XCTestCase {
 func testAppliesReadableDetailsAndPreservesUnknownFields() throws {
  let details = try CoffeePhotoDetails.parse(Data(#"{"name":" New coffee ","roaster":null,"origin":"Colombia","roastDate":"2026-10-20"}"#.utf8))
  let original = Coffee(name: "Old", roaster: "Manual roaster", photo: UUID().uuidString)
  let filled = details.applying(to: original)
  XCTAssertEqual(filled.name, "New coffee"); XCTAssertEqual(filled.roaster, original.roaster)
  XCTAssertEqual(filled.origin, "Colombia"); XCTAssertNotNil(filled.roastDate)
  XCTAssertEqual(filled.id, original.id); XCTAssertEqual(filled.photo, original.photo)
 }
 func testRejectsUnreadableAndMalformedResults() {
  for json in [#"{"name":null,"roaster":null,"origin":null,"roastDate":null}"#, #"{"name":"  ","roastDate":"2026-02-30"}"#, #"{"name":123}"#] {
   XCTAssertThrowsError(try CoffeePhotoDetails.parse(Data(json.utf8)))
  }
 }
 func testInvalidDatesDoNotReplaceExistingDate() throws {
  let original = Coffee(name: "Original", roastDate: Date(timeIntervalSince1970: 123))
  for date in ["2026-02-30", "10/12/26", "2026-13-01", "2026-1-01"] {
   let details = try CoffeePhotoDetails.parse(Data("{\"name\":\"Coffee\",\"roastDate\":\"\(date)\"}".utf8))
   XCTAssertNil(details.parsedRoastDate)
   XCTAssertEqual(details.applying(to: original).roastDate, original.roastDate)
  }
 }
}

private final class CoffeeExtractionStub: URLProtocol {
 override class func canInit(with request: URLRequest) -> Bool { true }
 override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
 override func startLoading() {
  var data = request.httpBody ?? Data()
  if let stream = request.httpBodyStream {
   stream.open(); defer { stream.close() }
   var buffer = [UInt8](repeating: 0, count: 4096)
   while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
  }
  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  XCTAssertEqual(body?["store"] as? Bool, false)
  let text = body?["text"] as? [String: Any]
  let format = text?["format"] as? [String: Any]
  XCTAssertEqual(format?["type"] as? String, "json_schema")
  XCTAssertEqual(format?["strict"] as? Bool, true)
  XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("input_image"))
  let extracted = #"{"name":"Test coffee","roaster":null,"origin":"Peru","roastDate":null}"#
  let response: [String: Any] = ["status": "completed", "output": [["content": [["type": "output_text", "text": extracted]]]]]
  client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
  client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: response))
  client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
}
extension CoffeePhotoDetailsTests {
 func testExtractsPhotoWithStructuredResponse() async throws {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [CoffeeExtractionStub.self]
  let session = URLSession(configuration: configuration)
  defer { session.invalidateAndCancel() }
  let details = try await RecipeGenerator().extractCoffee(jpeg: Data([1, 2]), apiKey: "test-placeholder", session: session)
  XCTAssertEqual(details.name, "Test coffee"); XCTAssertEqual(details.origin, "Peru")
 }
}
