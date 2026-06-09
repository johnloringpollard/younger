# Younger

Younger is a native SwiftUI daily wellness dashboard. It combines Apple Health activity and vital signals with WHOOP recovery, strain, sleep, and workout data, then turns them into clear red, yellow, and green daily goals.

## Architecture

- `Younger/`: iOS app using HealthKit and `ASWebAuthenticationSession`.
- `functions/`: Firebase Functions OAuth broker and WHOOP API proxy.
- Firestore: server-only storage for rotating WHOOP tokens, one-time tickets, and Younger sessions.
- `docs/`: GitHub Pages landing and OAuth return handoff.

WHOOP client credentials and refresh tokens never ship in the iOS app or the Pages site.

## Run the iOS app

1. Open `Younger.xcodeproj`.
2. Select your Apple development team.
3. Run on a physical iPhone to authorize Apple Health.
4. Use the Simulator with Demo Data enabled to explore the interface.

## Deploy WHOOP OAuth

The Firebase project is `younger-jlp`. Cloud Functions and Secret Manager require the Blaze billing plan.

1. Upgrade `younger-jlp` to Blaze in the Firebase console.
2. Create an app in the WHOOP Developer Dashboard.
3. Add this exact WHOOP redirect URI:

   `https://us-central1-younger-jlp.cloudfunctions.net/whoopCallback`

4. Enable these WHOOP scopes:

   `offline read:recovery read:cycles read:sleep read:workout read:body_measurement`

5. Store the WHOOP credentials:

   ```bash
   npx firebase-tools functions:secrets:set WHOOP_CLIENT_ID --project younger-jlp
   npx firebase-tools functions:secrets:set WHOOP_CLIENT_SECRET --project younger-jlp
   ```

6. Deploy:

   ```bash
   npx firebase-tools deploy --only functions,firestore --project younger-jlp
   ```

The GitHub Pages workflow publishes `docs/` to:

`https://johnloringpollard.github.io/younger`

## OAuth flow

1. Younger opens `whoopAuthStart`.
2. Firebase creates and validates OAuth state.
3. WHOOP returns the authorization code to `whoopCallback`.
4. Firebase exchanges it using Secret Manager and stores rotating tokens in Firestore.
5. GitHub Pages receives a five-minute, one-use ticket and opens `younger://oauth`.
6. The app exchanges the ticket for an opaque Younger session token.
7. WHOOP data and refresh requests continue through Firebase.

## Product note

The score is a transparent daily wellness score, not a diagnosis or literal biological-age calculation. The initial goals are defaults and should become personalized from user baselines over time.
