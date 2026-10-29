import Foundation

struct SecurityInfo: Equatable {
    let name: String
    let sector: String
    let assetClass: AssetClass
}

/// Offline classification for common US symbols. Alpaca's free API has no sector data,
/// so unknown symbols fall back to "Unclassified".
enum SectorDirectory {
    static let unclassified = "Unclassified"

    static let commonSectors = [
        "Technology", "Communication Services", "Consumer Discretionary", "Consumer Staples",
        "Financials", "Health Care", "Industrials", "Energy", "Utilities", "Materials",
        "Real Estate", "Broad Market", "International", "Bonds", "Commodities", "Cash", "Other"
    ]

    static func info(for symbol: String) -> SecurityInfo {
        let key = symbol.uppercased()
        return table[key] ?? SecurityInfo(name: key, sector: unclassified, assetClass: .equity)
    }

    private static func stock(_ name: String, _ sector: String) -> SecurityInfo {
        SecurityInfo(name: name, sector: sector, assetClass: .equity)
    }

    private static func fund(_ name: String, _ sector: String, _ assetClass: AssetClass = .etf) -> SecurityInfo {
        SecurityInfo(name: name, sector: sector, assetClass: assetClass)
    }

    private static let table: [String: SecurityInfo] = [
        "AAPL": stock("Apple", "Technology"),
        "MSFT": stock("Microsoft", "Technology"),
        "NVDA": stock("NVIDIA", "Technology"),
        "AMD": stock("Advanced Micro Devices", "Technology"),
        "INTC": stock("Intel", "Technology"),
        "AVGO": stock("Broadcom", "Technology"),
        "ORCL": stock("Oracle", "Technology"),
        "CRM": stock("Salesforce", "Technology"),
        "ADBE": stock("Adobe", "Technology"),
        "CSCO": stock("Cisco Systems", "Technology"),
        "IBM": stock("IBM", "Technology"),
        "QCOM": stock("Qualcomm", "Technology"),
        "PLTR": stock("Palantir", "Technology"),
        "SHOP": stock("Shopify", "Technology"),
        "INFY": stock("Infosys (ADR)", "Technology"),
        "GOOGL": stock("Alphabet Class A", "Communication Services"),
        "GOOG": stock("Alphabet Class C", "Communication Services"),
        "META": stock("Meta Platforms", "Communication Services"),
        "NFLX": stock("Netflix", "Communication Services"),
        "DIS": stock("Walt Disney", "Communication Services"),
        "AMZN": stock("Amazon", "Consumer Discretionary"),
        "TSLA": stock("Tesla", "Consumer Discretionary"),
        "MCD": stock("McDonald's", "Consumer Discretionary"),
        "NKE": stock("Nike", "Consumer Discretionary"),
        "JPM": stock("JPMorgan Chase", "Financials"),
        "BAC": stock("Bank of America", "Financials"),
        "GS": stock("Goldman Sachs", "Financials"),
        "MS": stock("Morgan Stanley", "Financials"),
        "V": stock("Visa", "Financials"),
        "MA": stock("Mastercard", "Financials"),
        "IBKR": stock("Interactive Brokers", "Financials"),
        "HOOD": stock("Robinhood", "Financials"),
        "BRK.B": stock("Berkshire Hathaway", "Financials"),
        "HDB": stock("HDFC Bank (ADR)", "Financials"),
        "IBN": stock("ICICI Bank (ADR)", "Financials"),
        "JNJ": stock("Johnson & Johnson", "Health Care"),
        "UNH": stock("UnitedHealth", "Health Care"),
        "LLY": stock("Eli Lilly", "Health Care"),
        "PFE": stock("Pfizer", "Health Care"),
        "MRK": stock("Merck", "Health Care"),
        "ABBV": stock("AbbVie", "Health Care"),
        "XOM": stock("Exxon Mobil", "Energy"),
        "CVX": stock("Chevron", "Energy"),
        "KO": stock("Coca-Cola", "Consumer Staples"),
        "PEP": stock("PepsiCo", "Consumer Staples"),
        "WMT": stock("Walmart", "Consumer Staples"),
        "COST": stock("Costco", "Consumer Staples"),
        "PG": stock("Procter & Gamble", "Consumer Staples"),
        "BA": stock("Boeing", "Industrials"),
        "CAT": stock("Caterpillar", "Industrials"),
        "GE": stock("GE Aerospace", "Industrials"),
        "UBER": stock("Uber", "Industrials"),
        "NEE": stock("NextEra Energy", "Utilities"),
        "AMT": SecurityInfo(name: "American Tower", sector: "Real Estate", assetClass: .realEstate),
        "SPY": fund("SPDR S&P 500 ETF", "Broad Market"),
        "VOO": fund("Vanguard S&P 500 ETF", "Broad Market"),
        "VTI": fund("Vanguard Total Stock Market ETF", "Broad Market"),
        "IWM": fund("iShares Russell 2000 ETF", "Broad Market"),
        "QQQ": fund("Invesco QQQ (Nasdaq-100)", "Technology"),
        "INDA": fund("iShares MSCI India ETF", "International"),
        "VXUS": fund("Vanguard Total International ETF", "International"),
        "TLT": fund("iShares 20+ Year Treasury", "Bonds", .bond),
        "BND": fund("Vanguard Total Bond Market", "Bonds", .bond),
        "GLD": fund("SPDR Gold Shares", "Commodities", .commodity),
        "SLV": fund("iShares Silver Trust", "Commodities", .commodity)
    ]
}
