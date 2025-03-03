# Investr App

An iOS application for tracking and managing investments.

## API Keys Setup

This app requires API keys to function properly. For security reasons, API keys are stored in a separate configuration file that is not committed to the repository.

### Setup Instructions

1. Copy the template file to create your own API keys file:
   ```
   cp Configuration/ApiKeys.plist.template Configuration/ApiKeys.plist
   ```

2. Open `ApiKeys.plist` in Xcode and replace the placeholder values with your actual API keys:
   - `SUPABASE_URL`: Your Supabase project URL
   - `SUPABASE_KEY`: Your Supabase API key
   - API keys for financial data providers (see below)

3. Make sure not to commit your `ApiKeys.plist` file to the repository (it should be already in `.gitignore`).

## Financial Data API Providers

Investr now uses multiple API providers with automatic failover to ensure reliable data access without hitting rate limits. You don't need to set up all providers - just at least one for cryptocurrency data and one for ETF/stock data.

### Recommended Providers

#### For Cryptocurrency Data:
- CryptoCompare (100K calls/month free): https://www.cryptocompare.com/
- CoinGecko (free tier without API key): https://www.coingecko.com/

#### For ETF & Stock Data:
- Financial Modeling Prep (250-300 calls/day free): https://financialmodelingprep.com/
- Alpha Vantage (500 calls/day free): https://www.alphavantage.co/

For more details about all available providers, their rate limits, and how to get API keys, see [API Integration Documentation](Documentation/APIIntegration.md).

## API Settings UI

You can add or update API keys at runtime through the in-app API Settings interface without needing to modify the ApiKeys.plist file. This makes it easy to try different providers.

## Running the App

When running the app from Xcode, ensure the `ApiKeys.plist` file is added to your project and included in the app target. The app will automatically read API keys from this file during initialization.

If any API key is missing or invalid, the app will display relevant warnings and try alternative providers. You can also set up API keys directly in the app using the API Settings interface.

## Advanced Features

### API Caching

The app includes a sophisticated caching system that reduces the number of API calls:
- In-memory cache for immediate access
- Persistent disk cache that survives app restarts
- Configurable cache durations (10 minutes for crypto, 20 minutes for ETF/stocks)

## Project Structure

- **API**: Contains all API-related code
  - **Core**: Core API infrastructure (managers, caching, rate limiting)
  - **Providers**: Individual API provider implementations
- **Configuration**: Configuration files and management
- **Services**: Business logic services
- **Views**: UI components
  - **Settings**: Settings-related views
- **Documentation**: Project documentation 