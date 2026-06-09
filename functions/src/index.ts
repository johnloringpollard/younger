import {createHash, randomBytes, randomUUID} from "node:crypto";
import {initializeApp} from "firebase-admin/app";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {defineSecret, defineString} from "firebase-functions/params";
import {onRequest} from "firebase-functions/v2/https";

initializeApp();

const db = getFirestore();
const region = "us-central1";
const whoopClientId = defineSecret("WHOOP_CLIENT_ID");
const whoopClientSecret = defineSecret("WHOOP_CLIENT_SECRET");
const whoopRedirectUri = defineString("WHOOP_REDIRECT_URI", {
  default: "https://us-central1-younger-jlp.cloudfunctions.net/whoopCallback",
});
const pagesBaseUrl = defineString("PAGES_BASE_URL", {
  default: "https://johnloringpollard.github.io/younger",
});

const whoopAuthorizationUrl = "https://api.prod.whoop.com/oauth/oauth2/auth";
const whoopTokenUrl = "https://api.prod.whoop.com/oauth/oauth2/token";
const whoopApiBase = "https://api.prod.whoop.com/developer/v2";
const requestedScopes = [
  "offline",
  "read:recovery",
  "read:cycles",
  "read:sleep",
  "read:workout",
  "read:body_measurement",
];

type TokenResponse = {
  access_token: string;
  refresh_token?: string;
  expires_in: number;
  scope?: string;
  token_type: string;
};

type ConnectionDocument = {
  accessToken: string;
  refreshToken?: string;
  expiresAt: Timestamp;
  scope?: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
};

const publicOptions = {
  region,
  cors: false,
  invoker: "public" as const,
  maxInstances: 10,
};

export const whoopAuthStart = onRequest(
  {...publicOptions, secrets: [whoopClientId]},
  async (request, response) => {
    if (request.method !== "GET") {
      response.status(405).send("Method not allowed");
      return;
    }

    const state = randomState();
    await db.collection("oauthStates").doc(state).set({
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
    });

    const authorizationUrl = new URL(whoopAuthorizationUrl);
    authorizationUrl.searchParams.set("client_id", whoopClientId.value());
    authorizationUrl.searchParams.set("redirect_uri", whoopRedirectUri.value());
    authorizationUrl.searchParams.set("response_type", "code");
    authorizationUrl.searchParams.set("scope", requestedScopes.join(" "));
    authorizationUrl.searchParams.set("state", state);

    response.set("Cache-Control", "no-store");
    response.redirect(302, authorizationUrl.toString());
  },
);

export const whoopCallback = onRequest(
  {...publicOptions, secrets: [whoopClientId, whoopClientSecret]},
  async (request, response) => {
    if (request.method !== "GET") {
      response.status(405).send("Method not allowed");
      return;
    }

    const state = singleQueryValue(request.query.state);
    const code = singleQueryValue(request.query.code);
    const oauthError = singleQueryValue(request.query.error);

    if (oauthError) {
      response.redirect(302, connectedPageUrl({error: oauthError}));
      return;
    }
    if (!state || !code || !(await consumeValidState(state))) {
      response.redirect(302, connectedPageUrl({error: "invalid_state"}));
      return;
    }

    try {
      const tokens = await exchangeAuthorizationCode(code);
      const connectionId = randomUUID();
      const sessionToken = secureToken();
      const ticket = secureToken();
      const now = Timestamp.now();

      await Promise.all([
        db.collection("whoopConnections").doc(connectionId).set({
          accessToken: tokens.access_token,
          refreshToken: tokens.refresh_token,
          expiresAt: Timestamp.fromMillis(Date.now() + tokens.expires_in * 1000),
          scope: tokens.scope,
          createdAt: now,
          updatedAt: now,
        } satisfies ConnectionDocument),
        db.collection("whoopSessions").doc(hashToken(sessionToken)).set({
          connectionId,
          createdAt: now,
        }),
        db.collection("oauthTickets").doc(hashToken(ticket)).set({
          sessionToken,
          createdAt: now,
          expiresAt: Timestamp.fromMillis(Date.now() + 5 * 60 * 1000),
        }),
      ]);

      response.set("Cache-Control", "no-store");
      response.redirect(302, connectedPageUrl({ticket}));
    } catch (error) {
      console.error("WHOOP callback failed", error);
      response.redirect(302, connectedPageUrl({error: "token_exchange_failed"}));
    }
  },
);

export const whoopExchangeTicket = onRequest(
  publicOptions,
  async (request, response) => {
    if (request.method !== "POST") {
      sendJson(response, 405, {error: "method_not_allowed"});
      return;
    }

    const ticket = stringBodyValue(request.body, "ticket");
    if (!ticket) {
      sendJson(response, 400, {error: "missing_ticket"});
      return;
    }

    const ticketReference = db.collection("oauthTickets").doc(hashToken(ticket));
    const sessionToken = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ticketReference);
      if (!snapshot.exists) return null;

      const data = snapshot.data();
      const expiresAt = data?.expiresAt as Timestamp | undefined;
      const value = data?.sessionToken as string | undefined;
      transaction.delete(ticketReference);

      if (!expiresAt || expiresAt.toMillis() <= Date.now()) return null;
      return value ?? null;
    });

    if (!sessionToken) {
      sendJson(response, 401, {error: "invalid_or_expired_ticket"});
      return;
    }

    sendJson(response, 200, {session_token: sessionToken});
  },
);

export const whoopSnapshot = onRequest(
  {...publicOptions, secrets: [whoopClientId, whoopClientSecret]},
  async (request, response) => {
    if (request.method !== "GET") {
      sendJson(response, 405, {error: "method_not_allowed"});
      return;
    }

    const connection = await authenticatedConnection(request.headers.authorization);
    if (!connection) {
      sendJson(response, 401, {error: "unauthorized"});
      return;
    }

    try {
      const accessToken = await validAccessToken(connection.id, connection.data);
      const [recoveries, cycles, sleeps, workouts] = await Promise.all([
        whoopRequest("recovery?limit=1", accessToken),
        whoopRequest("cycle?limit=1", accessToken),
        whoopRequest("activity/sleep?limit=1", accessToken),
        whoopRequest("activity/workout?limit=10", accessToken),
      ]);

      sendJson(response, 200, buildSnapshot(recoveries, cycles, sleeps, workouts));
    } catch (error) {
      console.error("WHOOP snapshot failed", error);
      sendJson(response, 502, {error: "whoop_request_failed"});
    }
  },
);

export const whoopDisconnect = onRequest(
  {...publicOptions, secrets: [whoopClientId, whoopClientSecret]},
  async (request, response) => {
    if (request.method !== "POST") {
      sendJson(response, 405, {error: "method_not_allowed"});
      return;
    }

    const sessionToken = bearerToken(request.headers.authorization);
    if (!sessionToken) {
      sendJson(response, 401, {error: "unauthorized"});
      return;
    }

    const authenticated = await authenticatedConnection(
      request.headers.authorization,
    );
    if (!authenticated) {
      sendJson(response, 401, {error: "unauthorized"});
      return;
    }

    try {
      const accessToken = await validAccessToken(
        authenticated.id,
        authenticated.data,
      );
      await revokeWhoopAccess(accessToken);
    } catch (error) {
      console.error("WHOOP revocation failed", error);
      sendJson(response, 502, {error: "whoop_revocation_failed"});
      return;
    }

    const sessionReference = db.collection("whoopSessions").doc(hashToken(sessionToken));
    const batch = db.batch();
    batch.delete(sessionReference);
    batch.delete(db.collection("whoopConnections").doc(authenticated.id));
    await batch.commit();
    response.status(204).send();
  },
);

async function consumeValidState(state: string): Promise<boolean> {
  const reference = db.collection("oauthStates").doc(state);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return false;

    const expiresAt = snapshot.data()?.expiresAt as Timestamp | undefined;
    transaction.delete(reference);
    return Boolean(expiresAt && expiresAt.toMillis() > Date.now());
  });
}

async function exchangeAuthorizationCode(code: string): Promise<TokenResponse> {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    client_id: whoopClientId.value(),
    client_secret: whoopClientSecret.value(),
    redirect_uri: whoopRedirectUri.value(),
  });
  return tokenRequest(body);
}

async function refreshAccessToken(refreshToken: string): Promise<TokenResponse> {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
    client_id: whoopClientId.value(),
    client_secret: whoopClientSecret.value(),
    scope: "offline",
  });
  return tokenRequest(body);
}

async function tokenRequest(body: URLSearchParams): Promise<TokenResponse> {
  const result = await fetch(whoopTokenUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body,
  });
  if (!result.ok) {
    throw new Error(`WHOOP token endpoint returned ${result.status}`);
  }
  return result.json() as Promise<TokenResponse>;
}

async function authenticatedConnection(
  authorization: string | undefined,
): Promise<{id: string; data: ConnectionDocument} | null> {
  const sessionToken = bearerToken(authorization);
  if (!sessionToken) return null;

  const session = await db.collection("whoopSessions").doc(hashToken(sessionToken)).get();
  const connectionId = session.data()?.connectionId as string | undefined;
  if (!connectionId) return null;

  const connection = await db.collection("whoopConnections").doc(connectionId).get();
  if (!connection.exists) return null;
  return {id: connectionId, data: connection.data() as ConnectionDocument};
}

async function validAccessToken(
  connectionId: string,
  connection: ConnectionDocument,
): Promise<string> {
  if (connection.expiresAt.toMillis() > Date.now() + 60_000) {
    return connection.accessToken;
  }
  if (!connection.refreshToken) {
    throw new Error("WHOOP refresh token is unavailable");
  }

  const tokens = await refreshAccessToken(connection.refreshToken);
  await db.collection("whoopConnections").doc(connectionId).update({
    accessToken: tokens.access_token,
    refreshToken: tokens.refresh_token ?? connection.refreshToken,
    expiresAt: Timestamp.fromMillis(Date.now() + tokens.expires_in * 1000),
    scope: tokens.scope ?? connection.scope,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return tokens.access_token;
}

async function whoopRequest(path: string, accessToken: string): Promise<unknown> {
  const result = await fetch(`${whoopApiBase}/${path}`, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: "application/json",
    },
  });
  if (!result.ok) {
    throw new Error(`WHOOP API returned ${result.status} for ${path}`);
  }
  return result.json();
}

async function revokeWhoopAccess(accessToken: string): Promise<void> {
  const result = await fetch(`${whoopApiBase}/user/access`, {
    method: "DELETE",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: "application/json",
    },
  });
  if (!result.ok && result.status !== 404) {
    throw new Error(`WHOOP revocation returned ${result.status}`);
  }
}

function buildSnapshot(
  recoveriesValue: unknown,
  cyclesValue: unknown,
  sleepsValue: unknown,
  workoutsValue: unknown,
): Record<string, number | null> {
  const recoveries = asRecordArray(recoveriesValue);
  const cycles = asRecordArray(cyclesValue);
  const sleeps = asRecordArray(sleepsValue);
  const workouts = asRecordArray(workoutsValue);
  const recovery = objectValue(recoveries[0], "score");
  const cycle = objectValue(cycles[0], "score");
  const sleep = objectValue(sleeps[0], "score");
  const stages = objectValue(sleep, "stage_summary");
  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);

  const zoneMilliseconds = workouts.reduce((total, workout) => {
    const start = stringValue(workout, "start");
    if (!start || new Date(start) < startOfToday) return total;
    const score = objectValue(workout, "score");
    const zones = objectValue(score, "zone_duration");
    return total +
      numberValue(zones, "zone_two_milli") +
      numberValue(zones, "zone_three_milli") +
      numberValue(zones, "zone_four_milli") +
      numberValue(zones, "zone_five_milli");
  }, 0);

  const sleepMilliseconds =
    numberValue(stages, "total_light_sleep_time_milli") +
    numberValue(stages, "total_slow_wave_sleep_time_milli") +
    numberValue(stages, "total_rem_sleep_time_milli");

  return {
    recovery_score: nullableNumber(recovery, "recovery_score"),
    strain: nullableNumber(cycle, "strain"),
    sleep_hours: sleepMilliseconds > 0 ? sleepMilliseconds / 3_600_000 : null,
    sleep_performance: nullableNumber(sleep, "sleep_performance_percentage"),
    hrv: nullableNumber(recovery, "hrv_rmssd_milli"),
    resting_heart_rate: nullableNumber(recovery, "resting_heart_rate"),
    respiratory_rate: nullableNumber(sleep, "respiratory_rate"),
    oxygen_saturation: nullableNumber(recovery, "spo2_percentage"),
    skin_temperature: nullableNumber(recovery, "skin_temp_celsius"),
    zone_minutes: zoneMilliseconds / 60_000,
  };
}

function connectedPageUrl(parameters: Record<string, string>): string {
  const url = new URL(`${pagesBaseUrl.value().replace(/\/$/, "")}/connected.html`);
  for (const [key, value] of Object.entries(parameters)) {
    url.searchParams.set(key, value);
  }
  return url.toString();
}

function randomState(): string {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = randomBytes(8);
  return Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join("");
}

function secureToken(): string {
  return randomBytes(32).toString("base64url");
}

function hashToken(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function bearerToken(authorization: string | undefined): string | null {
  const match = authorization?.match(/^Bearer\s+(.+)$/i);
  return match?.[1] ?? null;
}

function singleQueryValue(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function stringBodyValue(body: unknown, key: string): string | null {
  if (!body || typeof body !== "object") return null;
  const value = (body as Record<string, unknown>)[key];
  return typeof value === "string" ? value : null;
}

function asRecordArray(value: unknown): Record<string, unknown>[] {
  if (!value || typeof value !== "object") return [];
  const records = (value as Record<string, unknown>).records;
  if (!Array.isArray(records)) return [];
  return records.filter((item): item is Record<string, unknown> =>
    Boolean(item) && typeof item === "object",
  );
}

function objectValue(
  value: Record<string, unknown> | undefined,
  key: string,
): Record<string, unknown> {
  const result = value?.[key];
  return result && typeof result === "object" ?
    result as Record<string, unknown> :
    {};
}

function stringValue(value: Record<string, unknown>, key: string): string | null {
  const result = value[key];
  return typeof result === "string" ? result : null;
}

function numberValue(value: Record<string, unknown>, key: string): number {
  const result = value[key];
  return typeof result === "number" ? result : 0;
}

function nullableNumber(value: Record<string, unknown>, key: string): number | null {
  const result = value[key];
  return typeof result === "number" ? result : null;
}

function sendJson(
  response: {status: (code: number) => {json: (body: unknown) => void}},
  status: number,
  body: unknown,
): void {
  response.status(status).json(body);
}
