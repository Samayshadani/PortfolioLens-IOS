import XCTest
@testable import PortfolioLens

/// Fixtures mirror the shapes documented at https://docs.alpaca.markets.
final class AlpacaDecodingTests: XCTestCase {
    private let decoder = JSONDecoder.alpaca

    func testNanosecondTimestampsParse() {
        XCTAssertNotNil(AlpacaDate.parse("2024-03-11T13:31:00.123456789Z"))
        XCTAssertNotNil(AlpacaDate.parse("2024-03-11T13:31:00Z"))
        XCTAssertNotNil(AlpacaDate.parse("2024-03-11T09:31:00.5-04:00"))
        XCTAssertNil(AlpacaDate.parse("not a date"))
    }

    func testAccountMapping() throws {
        let json = """
        {"id":"abc","account_number":"PA123","status":"ACTIVE","currency":"USD","cash":"1500.25",
         "equity":"10250.75","last_equity":"10000","buying_power":"3000.50",
         "long_market_value":"8750.50","maintenance_margin":"2187.62","pattern_day_trader":false}
        """
        let account = AlpacaMapper.account(try decoder.decode(AlpacaAccountDTO.self, from: Data(json.utf8)))
        XCTAssertEqual(account.accountNumber, "PA123")
        XCTAssertEqual(account.cash, Decimal(string: "1500.25"))
        XCTAssertEqual(account.lastEquity, 10000)
        XCTAssertEqual(account.buyingPower, Decimal(string: "3000.50"))
    }

    func testShortPositionGetsNegativeQuantity() throws {
        let json = """
        [{"asset_id":"x","symbol":"TSLA","exchange":"NASDAQ","asset_class":"us_equity","qty":"5","side":"short",
          "avg_entry_price":"250.00","market_value":"-1240.00","current_price":"248.00","lastday_price":"251.00"}]
        """
        let positions = try decoder.decode([AlpacaPositionDTO].self, from: Data(json.utf8)).map(AlpacaMapper.position)
        XCTAssertEqual(positions.first?.quantity, -5)
        XCTAssertEqual(positions.first?.lastDayPrice, 251)
        XCTAssertTrue(positions.first?.isStreamable ?? false)
    }

    func testOrderMapping() throws {
        let json = """
        {"id":"o1","client_order_id":"c1","created_at":"2024-03-16T18:38:01.942282Z","symbol":"AAPL",
         "qty":"2","filled_qty":"2","filled_avg_price":"171.25","side":"buy","type":"limit",
         "time_in_force":"day","limit_price":"172","status":"filled"}
        """
        let order = AlpacaMapper.order(try decoder.decode(AlpacaOrderDTO.self, from: Data(json.utf8)))
        XCTAssertEqual(order.side, .buy)
        XCTAssertEqual(order.filledAveragePrice, Decimal(string: "171.25"))
        XCTAssertEqual(order.limitPrice, 172)
        XCTAssertFalse(order.isOpen)
    }

    func testSnapshotsWithMissingSymbol() throws {
        let json = """
        {"AAPL":{"latestTrade":{"t":"2024-03-11T19:59:59.123456Z","x":"V","p":172.5,"s":100,"c":["@"],"i":1,"z":"C"},
                 "dailyBar":{"t":"2024-03-11T04:00:00Z","o":170,"h":173,"l":169.5,"c":172.4,"v":51234,"n":900,"vw":171.8},
                 "prevDailyBar":{"t":"2024-03-08T05:00:00Z","o":168,"h":171,"l":167,"c":170,"v":61234,"n":1000,"vw":169.9}},
         "NOPE":null}
        """
        let response = try decoder.decode([String: AlpacaSnapshotDTO?].self, from: Data(json.utf8))
        let quote = try XCTUnwrap(response["AAPL"].flatMap { $0 }.flatMap { AlpacaMapper.quote(symbol: "AAPL", snapshot: $0) })
        XCTAssertEqual(quote.price, Decimal(string: "172.5"))
        XCTAssertEqual(quote.previousClose, 170)
        XCTAssertEqual(quote.changePercent?.rounded(scale: 4), Decimal(string: "0.0147"))
    }

    func testStreamMessages() throws {
        let json = """
        [{"T":"success","msg":"authenticated"},
         {"T":"t","S":"AAPL","i":52983525029461,"x":"V","p":172.31,"s":100,"t":"2024-03-11T14:30:00.12345678Z","c":["@"],"z":"C"},
         {"T":"error","code":402,"msg":"auth failed"}]
        """
        let messages = try decoder.decode([AlpacaStreamMessage].self, from: Data(json.utf8))
        XCTAssertEqual(messages.map(\.type), ["success", "t", "error"])
        XCTAssertEqual(messages[1].symbol, "AAPL")
        XCTAssertEqual(messages[1].price?.rounded(scale: 2), Decimal(string: "172.31"))
        XCTAssertEqual(messages[2].code, 402)
        XCTAssertFalse(StreamError.server(code: 402, message: "auth failed").isRetryable)
        XCTAssertTrue(StreamError.server(code: 406, message: "connection limit exceeded").isRetryable)
    }

    func testOrderPayloadEncoding() throws {
        let request = OrderRequest(symbol: "aapl", quantity: Decimal(string: "1.5")!, side: .buy,
                                   type: .limit, timeInForce: .day, limitPrice: 170)
        let data = try JSONEncoder.alpaca.encode(AlpacaMapper.payload(for: request))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["symbol"] as? String, "AAPL")
        XCTAssertEqual(object["qty"] as? String, "1.5")
        XCTAssertEqual(object["time_in_force"] as? String, "day")
        XCTAssertEqual(object["limit_price"] as? String, "170")
    }
}
