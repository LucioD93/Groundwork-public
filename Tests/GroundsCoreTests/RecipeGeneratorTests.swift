import XCTest
@testable import GroundsCore

final class RecipeGeneratorTests: XCTestCase {
 func testExtractsRecipeAndIgnoresOtherOutput() throws {
  let data = Data(#"{"status":"completed","output":[{"type":"reasoning"},{"content":[{"type":"output_text","text":"18 g coffee"},{"type":"refusal","text":"ignored"},{"type":"output_text","text":"36 g yield"}]}]}"#.utf8)
  XCTAssertEqual(try RecipeGenerator.recipe(from: data), "18 g coffee\n36 g yield")
 }
 func testRejectsIncompleteAndEmptyRecipes() {
  for json in [#"{"status":"incomplete","output":[]}"#, #"{"status":"completed","output":[]}"#, #"{"status":"completed","output":[{"content":[{"type":"refusal"}]}]}"#] {
   XCTAssertThrowsError(try RecipeGenerator.recipe(from: Data(json.utf8)))
  }
 }
 func testRequestAndAuthenticationFailure() async throws {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [RecipeStub.self]
  let session = URLSession(configuration: configuration)
  defer { session.invalidateAndCancel() }
  do {
   _ = try await RecipeGenerator().generate(coffee: Coffee(name: "Test"), method: .aeroPress, jpeg: Data([1, 2]), apiKey: "test-placeholder", session: session)
   XCTFail("Expected rejection")
  } catch { XCTAssertTrue(error.localizedDescription.contains("Replace it in Settings")) }
 }
}

private final class RecipeStub: URLProtocol {
 override class func canInit(with request: URLRequest) -> Bool { true }
 override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
 override func startLoading() {
  XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
  XCTAssertEqual(request.httpMethod, "POST")
  XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-placeholder")
  // URLSession may expose the encoded body as a stream.
  var data = request.httpBody ?? Data()
  if let stream = request.httpBodyStream {
   stream.open(); defer { stream.close() }
   var buffer = [UInt8](repeating: 0, count: 4096)
   while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
  }
  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  XCTAssertEqual(body?["store"] as? Bool, false)
  XCTAssertEqual(body?["model"] as? String, "gpt-4.1-mini")
  XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("AeroPress") == true)
  XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("input_image") == true)
  client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
  client?.urlProtocol(self, didLoad: Data())
  client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
}
