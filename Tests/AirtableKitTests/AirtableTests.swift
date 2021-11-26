import Foundation

import XCTest
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import AirtableKit

class AirtableTests: XCTestCase {
    
    var service: Airtable!

    override func setUp() {
        service = Airtable(baseID: "base123", apiKey: "key123")
    }
    
    func testValidRequest() async throws {
        let request = URLRequest(url: URL(string: "http://example.com")!)
        stub(condition: isHost("example.com") && isMethodGET()) { _ in
            HTTPStubsResponse(jsonObject: ["key": "value"], statusCode: 200, headers: nil)
        }
        
        let response = try await service.performRequest(request, decoder: jsonDecoder(data:))
        XCTAssertEqual(response as? [String : String], ["key": "value"])
    }
    
    func testInvalidRequest() async throws {
        let request: URLRequest? = nil
        
        do {
            _ = try await service.performRequest(request, decoder: jsonDecoder(data:))
        } catch {
            XCTAssertEqual(error as? AirtableError, AirtableError.invalidParameters(operation: "performRequest(_:decoder:)", parameters: [request as Any]))
        }
    }
    
    func testHttpError() async throws {
        let request = URLRequest(url: URL(string: "http://example.com")!)
        stub(condition: isHost("example.com") && isMethodGET()) { _ in
            HTTPStubsResponse(data: Data(), statusCode: 404, headers: nil)
        }
        
        do {
            _ = try await service.performRequest(request, decoder: jsonDecoder(data:))
        } catch {
            XCTAssertEqual(error as? AirtableError, AirtableError.notFound)
        }
    }
    
    func testURLError() async throws {
        let request = URLRequest(url: URL(string: "http://example.com")!)
        stub(condition: isHost("example.com") && isMethodGET()) { _ in
            HTTPStubsResponse(error: URLError(.notConnectedToInternet))
        }
        
        do {
            _ = try await service.performRequest(request, decoder: jsonDecoder(data:))
        } catch {
            XCTAssertEqual(error as? AirtableError, AirtableError.network(URLError(.notConnectedToInternet)))
        }
    }
    
    func checkAPIKey(_ request: URLRequest?) {
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer key123")
    }
    
    func testCreateSimpleRequest() async throws {
        let request = service.buildRequest(method: "DELETE", path: "users/1")
        
        XCTAssertEqual(request?.httpMethod, "DELETE")
        XCTAssertTrue(try XCTUnwrap(request?.url?.absoluteString).hasSuffix("/users/1"))
        XCTAssertNil(request?.httpBody)
        checkAPIKey(request)
        XCTAssertNil(request?.value(forHTTPHeaderField: "Content-Type"))
    }
    
    func testCreateQueryRequest() async throws {
        let queryItems = [URLQueryItem(name: "fields[]", value: "name"), URLQueryItem(name: "fields[]", value: "email")]
        let request = service.buildRequest(method: "GET", path: "/users", queryItems: queryItems)
        
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertTrue(try XCTUnwrap(request?.url?.absoluteString).hasSuffix("/users?fields%5B%5D=name&fields%5B%5D=email"))
        XCTAssertNil(request?.httpBody)
        checkAPIKey(request)
        XCTAssertNil(request?.value(forHTTPHeaderField: "Content-Type"))
    }
    
    func testCreatePayloadRequest() async throws {
        let request = service.buildRequest(method: "POST", path: "/users", payload: ["name": "John"])
        
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertTrue(try XCTUnwrap(request?.url?.absoluteString).hasSuffix("/users"))
        XCTAssertEqual(request?.httpBody, #"{"name":"John"}"#.data(using: .utf8))
        checkAPIKey(request)
    }
    
    func testCreateCompleteRequest() async throws {
        let queryItems = [URLQueryItem(name: "fields[]", value: "name")]
        let request = service.buildRequest(method: "PUT", path: "users", queryItems: queryItems, payload: ["name": "Jane"])
        
        XCTAssertEqual(request?.httpMethod, "PUT")
        XCTAssertTrue(try XCTUnwrap(request?.url?.absoluteString).hasSuffix("/users?fields%5B%5D=name"))
        checkAPIKey(request)
        XCTAssertEqual(request?.httpBody, #"{"name":"Jane"}"#.data(using: .utf8))
    }
}

func jsonDecoder(data: Data) throws -> [String: Any]? {
    try JSONSerialization.jsonObject(with: data) as? [String: Any]
}
