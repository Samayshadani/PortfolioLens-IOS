# PortfolioLens

A SwiftUI trading companion that shows how exposed you really are before you trade.

Most broker apps show positions one by one. PortfolioLens adds a **Lens**: it combines your broker account with assets you hold elsewhere (Indian stocks, mutual funds, FDs, gold, cash in INR), converts everything to one currency, and shows:

- **Exposure** by sector, currency, asset class and holding, with plain-language risk insights
- **Diversification score**, which says how many equal-weight holdings your portfolio actually behaves like
- **What-if simulator**, which shows how a trade would change your weights, cash, buying power and sector mix *before* you place it

It also covers a broker app's basics: live streaming quotes, charts, paper trading (market and limit orders), order history, price alerts with notifications, and Face ID lock.

## Tech

| Layer | Choice |
|---|---|
| UI | SwiftUI, Swift Charts, iOS 17 Observation (`@Observable`) |
| Concurrency | async/await, actors, `AsyncThrowingStream` for the WebSocket |
| Database | SwiftData (watchlist, price alerts, outside holdings) |
| Secrets | Keychain (API keys never touch UserDefaults or source code) |
| Broker API | Alpaca paper trading REST and market-data WebSocket (IEX feed, free) |
| FX rates | Frankfurter (ECB reference rates, free, no key) |
| Money maths | `Decimal` everywhere, never `Double` |
| Tests | XCTest for every calculation and for parsing real API payloads |

```
PortfolioLens/
  App/            entry point, tab layout, lock and alert banner
  State/          MarketStore (live data), settings, FX, alerts, dependency setup
  Domain/         pure logic: portfolio maths, exposure, what-if, currency
  Services/       Alpaca client, demo simulator, FX, Keychain, Face ID, notifications
  Models/         API models and SwiftData models
  Features/       Portfolio, Markets, Lens, Trading, Settings screens
  DesignSystem/   theme and reusable components
PortfolioLensTests/
```

### Design decisions worth talking about in an interview

- **`BrokerageService` protocol.** The UI never knows whether it's talking to Alpaca or to the built-in `MockBrokerageService` actor. Swapping brokers (for example, adding IBKR's Web API) means writing one new class.
- **Tick coalescing.** WebSocket trades are buffered and published every 250 ms, so a burst of trades re-renders the UI once instead of hundreds of times.
- **Reconnect with exponential backoff.** Up to 30 s between attempts. It doesn't retry errors that can't fix themselves, such as bad keys or too many symbols.
- **Gross exposure.** Shorts count at their absolute size. Margin debt counts as zero rather than inflating the total.
- **Never silently wrong.** If a currency can't be converted, the app says so instead of counting it as 0.

## 1. Get your free API keys (5 minutes)

### Alpaca (paper trading and market data)
1. Go to <https://app.alpaca.markets/signup> and sign up with your email. Paper-only accounts are free and open to users outside the US.
2. Verify your email and log in. Make sure the dashboard is set to **Paper Trading** (top-left account switcher).
3. On the paper dashboard home page, find **API Keys** on the right and click **Generate New Keys** (or **View**).
4. Copy the **Key ID** (starts with `PK`) and the **Secret Key**. The secret is shown only once.
5. The paper account starts with $100,000 of virtual money. You can reset it from the dashboard at any time.

Free plan limits: real-time IEX prices, up to 30 streamed symbols, one WebSocket connection, 200 API calls per minute.

### Frankfurter (exchange rates)
Nothing to do. It needs no account or key.

## 2. Build on a Mac

Requirements: macOS with **Xcode 16 or newer**.

```bash
brew install xcodegen          # one-time (install Homebrew from brew.sh first)
cd "PortfolioLens iOS"
xcodegen generate              # creates PortfolioLens.xcodeproj from project.yml
open PortfolioLens.xcodeproj
```

In Xcode:
1. Select the **PortfolioLens** target, open **Signing & Capabilities**, choose your Apple ID under **Team**, and change the bundle ID from `com.example.portfoliolens` to something unique (e.g. `com.yourname.portfoliolens`).
2. Choose an iPhone simulator, or your own iPhone. A real device needs Developer Mode turned on in Settings, then Privacy & Security.
3. Press **⌘R** to run and **⌘U** to run the unit tests.

**Without XcodeGen:** create a new iOS App project in Xcode named `PortfolioLens` (SwiftUI, Swift, iOS 17). Delete its template `ContentView.swift` and `PortfolioLensApp.swift`, then drag in the `PortfolioLens/` folder ("Create groups"). Add `NSFaceIDUsageDescription` to the target's Info tab. For tests, add a Unit Testing Bundle target and drag in `PortfolioLensTests/`.

## 3. Use it

1. The first launch runs in **Demo mode**: a simulated market with a starter portfolio. Everything works offline, including orders.
2. Open **Settings → Alpaca paper trading**, paste your Key ID and Secret, and tap **Save & connect**. The app switches to your real paper account.
3. Live prices stream only while the US market is open, 9:30 AM–4:00 PM New York time (**7:00 PM–1:30 AM IST**, an hour later when the US is on standard time). Outside those hours you see the last price.
4. Try it out:
   - **Markets**: add symbols, open one, buy a few shares, set a price alert.
   - **Portfolio → Outside holdings**: add an INR mutual fund or FD, then set **Base currency** to INR.
   - **Lens**: check your exposure, then go to **What-if** and test a big trade.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Your API keys were rejected" | You pasted live keys or mixed up key and secret. Generate new **paper** keys. |
| Status stays "Connecting" or "Reconnecting" | Another device is streaming with the same keys (the free plan allows one connection). Close it. |
| Chart says "No trades in this range" | The market is closed and the 1D range is empty. Try 1M. |
| No price-alert notifications | Allow notifications when asked, or enable them in iOS Settings → PortfolioLens. |

## Roadmap ideas
- Home-screen widget and Live Activity for price alerts (WidgetKit + ActivityKit)
- IBKR Web API connector as a second `BrokerageService`
- Historical performance chart from Alpaca's `/account/portfolio/history`

*Learning project. Paper trading only, and nothing here is investment advice.*
