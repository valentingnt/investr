# Investr App

An iOS application for tracking and managing investments.

## API Keys Setup

This app requires API keys to function properly. For security reasons, API keys are stored in a separate configuration file that is not committed to the repository.

### Setup Instructions

1. Copy the template file to create your own API keys file:
   ```
   cp ApiKeys.plist.template ApiKeys.plist
   ```

2. Open `ApiKeys.plist` in Xcode and replace the placeholder values with your actual API keys:
   - `SUPABASE_URL`: Your Supabase project URL
   - `SUPABASE_KEY`: Your Supabase API key
   - `RAPIDAPI_KEY`: Your RapidAPI key for ETF and Crypto services

3. Make sure not to commit your `ApiKeys.plist` file to the repository (it should be already in `.gitignore`).

## Running the App

When running the app from Xcode, ensure the `ApiKeys.plist` file is added to your project and included in the app target. The app will automatically read API keys from this file during initialization.

If any API key is missing or invalid, the app will display relevant warnings and fallback to mock data where possible. 