# API Integration

This document provides detailed information about the API integration in the Investr app.

## API Architecture

The Investr app uses a multi-provider architecture with automatic failover to ensure reliable data access. The key components are:

1. **API Manager**: Coordinates between providers and handles failover
2. **API Key Manager**: Manages API keys from different sources
3. **API Response Cache**: Caches API responses to reduce API calls
4. **API Rate Limiter**: Prevents hitting API rate limits

## API Providers

### Cryptocurrency Data Providers

| Provider | Free Tier Limits | API Key Required | Notes |
|----------|------------------|------------------|-------|
| CryptoCompare | 100K calls/month | Yes | Primary provider |
| CoinGecko | 10-50 calls/min | No (but recommended) | Works without API key |
| CoinAPI | 100 calls/day | Yes | Additional provider |

### ETF & Stock Data Providers

| Provider | Free Tier Limits | API Key Required | Notes |
|----------|------------------|------------------|-------|
| Financial Modeling Prep | 250-300 calls/day | Yes | Primary provider |
| Alpha Vantage | 5 calls/min, 500 calls/day | Yes | Alternative provider |
| TwelveData | 8 calls/min, 800 calls/day | Yes | Additional provider |

## Getting API Keys

### CryptoCompare
1. Visit [CryptoCompare](https://www.cryptocompare.com/)
2. Create an account and go to the API section
3. Generate a free API key

### CoinGecko
1. Visit [CoinGecko](https://www.coingecko.com/)
2. Create an account and subscribe to a plan
3. Get your API key from the dashboard

### Financial Modeling Prep
1. Visit [Financial Modeling Prep](https://financialmodelingprep.com/)
2. Create an account and go to the API section
3. Get your free API key

### Alpha Vantage
1. Visit [Alpha Vantage](https://www.alphavantage.co/)
2. Request a free API key

## Advanced Features

### API Caching

The app includes a sophisticated caching system that reduces the number of API calls:
- In-memory cache for immediate access
- Persistent disk cache that survives app restarts
- Configurable cache durations (10 minutes for crypto, 20 minutes for ETF/stocks)

### Rate Limiting

The app includes an advanced rate limiter that:
- Tracks API calls per provider
- Ensures we don't exceed rate limits
- Automatically distributes calls over time
- Provides backoff mechanisms when limits are approached

## Best Practices

1. **Register for multiple APIs**: Having multiple API providers increases reliability
2. **Start with the recommended providers**: CryptoCompare and Financial Modeling Prep have generous free tiers
3. **Use the API Settings UI**: Add your API keys through the Settings interface
4. **Monitor usage**: Be aware of your usage patterns to avoid hitting limits

## Troubleshooting

If you experience issues with data retrieval:

1. Check that you have at least one valid API key for each asset type (crypto and ETF/stocks)
2. Use the "Test API Connections" function in the API Settings
3. Try clearing the API cache
4. Consult each provider's documentation for any service disruptions

## Technical Implementation

The API system consists of several components:

- `APIManager`: Coordinates between providers and handles failover
- `APIProvider` protocol: Interface for individual providers
- `APIResponseCache`: Manages caching
- `AdvancedAPIRateLimiter`: Handles rate limiting
- Provider implementations (e.g., `CryptoCompareProvider`, `FinancialModelingPrepProvider`, etc.)

This architecture makes it easy to add new data providers in the future. 