import Foundation
import XCTest

@testable import NexusApp

final class CookieStorageTests: XCTestCase {
    func testSerializeCookies() {
        let url = URL(string: "https://example.com")!
        let cookieStorage = HTTPCookieStorage.shared
        
        // Create a test cookie
        let properties: [HTTPCookiePropertyKey: Any] = [
            .name: "testCookie",
            .value: "testValue",
            .domain: "example.com",
            .path: "/"
        ]
        
        guard let cookie = HTTPCookie(properties: properties) else {
            XCTFail("Failed to create test cookie")
            return
        }
        
        cookieStorage.setCookie(cookie)
        
        // Serialize cookies
        let data = CookieStorage.serializeCookies(for: url, from: cookieStorage)
        XCTAssertNotNil(data, "Should serialize cookies")
        
        // Clean up
        cookieStorage.deleteCookie(cookie)
    }
    
    func testDeserializeCookies() {
        let url = URL(string: "https://example.com")!
        
        // Create serialized cookie data in string format
        let cookieString = "testCookie=testValue"
        guard let data = cookieString.data(using: .utf8) else {
            XCTFail("Failed to create cookie data")
            return
        }
        
        // Deserialize
        let cookies = CookieStorage.deserializeCookies(data, for: url)
        XCTAssertEqual(cookies.count, 1, "Should deserialize one cookie")
        XCTAssertEqual(cookies.first?.name, "testCookie")
        XCTAssertEqual(cookies.first?.value, "testValue")
    }
    
    func testParseCookieString() {
        let url = URL(string: "https://example.com")!
        let cookieString = "session=abc123; user=john"
        
        let cookies = CookieStorage.parseCookieString(cookieString, for: url)
        XCTAssertEqual(cookies.count, 2, "Should parse two cookies")
        XCTAssertEqual(cookies.first?.name, "session")
        XCTAssertEqual(cookies.first?.value, "abc123")
        XCTAssertEqual(cookies.last?.name, "user")
        XCTAssertEqual(cookies.last?.value, "john")
    }
    
    func testStoreCookies() {
        let url = URL(string: "https://example.com")!
        let cookieStorage = HTTPCookieStorage.shared
        
        // Create cookie data
        let cookieString = "test=value"
        guard let data = cookieString.data(using: .utf8) else {
            XCTFail("Failed to create cookie data")
            return
        }
        
        // Store cookies
        CookieStorage.storeCookies(data, for: url, in: cookieStorage)
        
        // Verify cookies were stored
        let storedCookies = cookieStorage.cookies(for: url)
        XCTAssertNotNil(storedCookies, "Cookies should be stored")
        
        // Clean up
        storedCookies?.forEach { cookieStorage.deleteCookie($0) }
    }
}
