// Tests/SwiflowCLITests/RuntimeFilesTests.swift
import Testing
@testable import SwiflowCLI

@Suite("RuntimeFiles.usesRegions")
struct RuntimeFilesTests {

    @Test("true when index.html references the regions script")
    func positive() {
        let html = """
        <body>
          <script src="swiflow-driver.js"></script>
          <script type="module" src="swiflow-regions.js"></script>
        </body>
        """
        #expect(RuntimeFiles.usesRegions(indexHTML: html) == true)
    }

    @Test("false for a plain page with no regions reference")
    func negative() {
        let html = """
        <body>
          <script src="swiflow-driver.js"></script>
        </body>
        """
        #expect(RuntimeFiles.usesRegions(indexHTML: html) == false)
    }

    @Test("true regardless of quote style or surrounding whitespace")
    func quoteRobust() {
        #expect(RuntimeFiles.usesRegions(indexHTML: "<script src='swiflow-regions.js' >") == true)
    }
}
