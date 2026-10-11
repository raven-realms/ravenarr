import XCTest
@testable import Ravenarr

/// These field shapes (certification nested under `releases`/`contentRatings`,
/// trailers under `relatedVideos`) were verified directly against Overseerr's
/// own TypeScript source rather than guessed — these tests pin that shape so
/// a future refactor can't silently drift from what the real API sends.
final class MediaDetailsDecodingTests: XCTestCase {
    func testMovieCertification() throws {
        let json = """
        {
          "id": 100,
          "title": "Test Movie",
          "releases": {
            "results": [
              { "iso_3166_1": "CA", "release_dates": [{ "certification": "14A" }] },
              { "iso_3166_1": "US", "release_dates": [{ "certification": "PG-13" }] }
            ]
          }
        }
        """
        let details = try JSONDecoder().decode(MediaDetails.self, from: Data(json.utf8))
        XCTAssertEqual(details.certification, "PG-13", "must pick the US entry, not just the first one")
    }

    func testTVContentRating() throws {
        let json = """
        {
          "id": 200,
          "name": "Test Show",
          "contentRatings": {
            "results": [
              { "iso_3166_1": "US", "rating": "TV-MA" }
            ]
          }
        }
        """
        let details = try JSONDecoder().decode(MediaDetails.self, from: Data(json.utf8))
        XCTAssertEqual(details.certification, "TV-MA")
    }

    func testNoCertificationAvailable() throws {
        let json = """
        { "id": 300, "title": "No Rating" }
        """
        let details = try JSONDecoder().decode(MediaDetails.self, from: Data(json.utf8))
        XCTAssertNil(details.certification)
    }

    func testTrailerURLFromYouTubeVideo() throws {
        let json = """
        {
          "id": 400,
          "title": "Trailer Movie",
          "relatedVideos": [
            { "key": "notATrailer", "site": "YouTube", "type": "Clip", "name": "Clip" },
            { "key": "abc123", "site": "YouTube", "type": "Trailer", "name": "Official Trailer" }
          ]
        }
        """
        let details = try JSONDecoder().decode(MediaDetails.self, from: Data(json.utf8))
        XCTAssertEqual(details.trailerURL, URL(string: "https://www.youtube.com/watch?v=abc123"))
    }

    func testNoTrailerAvailable() throws {
        let json = """
        { "id": 500, "title": "No Trailer" }
        """
        let details = try JSONDecoder().decode(MediaDetails.self, from: Data(json.utf8))
        XCTAssertNil(details.trailerURL)
    }
}
