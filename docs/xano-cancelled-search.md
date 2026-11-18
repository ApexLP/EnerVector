# Data center news search — setup

EnerVector's **Cancelled Projects › Data centers (news)** tab calls one Xano endpoint. Xano holds the
Claude API key and asks Claude to search the web for cancelled data center projects in a state.
The app never sees the Claude key.

```
iPhone app ──POST {"state": "Virginia"}──▶ Xano endpoint ──▶ Claude API (web search)
           ◀──────── Claude's response, passed through unchanged ◀────────┘
```

Allow about 20 minutes. Menu names below are from memory of each site; if one is labeled
slightly differently, look for the closest match.

---

## Step 1 — Claude API key and spend limit (platform.claude.com)

1. Go to **https://platform.claude.com** and sign in (or sign up) with your work email.
   If asked, create an organization named **Apex Lead Pros**.
2. **Add billing.** Open **Settings › Billing** and add a card, then buy a starting amount of
   credits — $10–$20 is plenty to test. Without credits, every request fails with
   "credit balance is too low".
3. **Set a spend limit.** In **Settings › Limits**, set a **monthly spend limit** (e.g. $25). Requests
   stop when it's reached, so a bug or leaked key can't run up a large bill.
4. **Create the key.** Open **API Keys › Create Key**, name it `EnerVector Xano`, and click **Create**.
5. **Copy the key now.** It starts with `sk-ant-` and is shown only once. Paste it straight into
   Xano in Step 2. Don't email it, put it in the app, or commit it to GitHub. If you lose it,
   delete it and create a new one.

**Cost:** each search is one Claude Opus 5.5 request that runs up to 6 web searches. You pay for the
tokens plus a fee per web search. Current prices: https://platform.claude.com/docs/en/about-claude/pricing.
After your first few searches, check **Usage** in the console to see the real cost per search.

---

## Step 2 — Environment variables (Xano)

1. Open your Xano workspace. Go to **Settings** (gear icon) › **Environment Variables**.
2. Add **`ANTHROPIC_API_KEY`** with the `sk-ant-…` key from Step 1.
3. Add **`ENERVECTOR_APP_KEY`** with a long random string you make up. To generate one on your Mac:
   ```bash
   openssl rand -hex 24
   ```
   Save this value somewhere safe (e.g. your password manager). You'll type it into the app in Step 4.
4. Save.

**Why two keys?** The Claude key is the expensive one and stays only in Xano. The app key is a
password the app sends with each search, so random people who find the endpoint URL can't run
searches on your bill. It isn't perfect protection (someone could dig it out of the app), so also
keep the spend limit from Step 1.

---

## Step 3 — The `cancelled_datacenters` endpoint (Xano)

### 3a. Create it

1. Go to **API** in the left sidebar. Open an existing API group or click **Add API Group** and
   name it `enervector`.
2. Click **Add API Endpoint › Custom endpoint**.
   - Name/path: `cancelled_datacenters`
   - Verb: **POST**
   - Authentication: **none** (the app key check below protects it)
3. Click **Save**. Xano opens the endpoint's function stack.

### 3b. Input

In the **Inputs** panel, add one input: type **text**, name **`state`**, required.

### 3c. Function stack — add these in order

**1. Check the app key** — *Utility Functions › Precondition*
- Condition: `$env.$http_headers|get:"x-app-key"` **equals** `$env.ENERVECTOR_APP_KEY`
  (if Xano keeps the header's original capitalization, use `"X-App-Key"` instead)
- Error type: **Access Denied** · Message: `Invalid app key`

**2. Check the state** — *Utility Functions › Precondition*
- Condition: `$input.state|strlen` **is less than or equal to** `30`
  **and** `$input.state|regex_matches:"/^[A-Za-z .]+$/"` **is true**
- Error type: **Bad Request** · Message: `Invalid state`
- This keeps quotes and other characters out of the request body built next.

**3. The request template** — *Variables › Create Variable*
- Name: `template`, type: **text**
- Value: open [`claude-request-template.json`](claude-request-template.json), copy **all** of it,
  and paste it in. It contains the placeholder `{{STATE}}`.

**4. Fill in the state** — *Variables › Create Variable*
- Name: `body`
- Value: `$var.template|replace:"{{STATE}}":$input.state|json_decode`

**5. Call Claude** — *APIs › External API Request*
- URL: `https://api.anthropic.com/v1/messages`
- Method: **POST**
- Params (body): `$var.body`
- Headers (one per line, `name: value`):
  - `content-type: application/json`
  - `"x-api-key: "|concat:$env.ANTHROPIC_API_KEY`
  - `anthropic-version: 2026-10-21`
  - `anthropic-beta: server-side-fallback-2026-07-01`
- Timeout: **240** seconds (searches usually take 30–120 seconds)
- Return as: `api_request`

**6. Check it worked** — *Utility Functions › Precondition*
- Condition: `$var.api_request.response.status` **equals** `200`
- Error type: **Bad Request** · Message: `Claude request failed`
- To see why it failed while testing, temporarily return `$var.api_request.response.result`
  instead (it holds Claude's error message).

### 3d. Response

In the **Response** panel, return **`$var.api_request.response.result`** (Claude's JSON, unchanged).

### 3e. Rate limit (if your Xano plan has it)

In the endpoint's settings, turn on rate limiting, e.g. **20 requests per hour**.

### 3f. Copy the endpoint URL

At the top of the API group, Xano shows the **base URL**, like
`https://x8ki-letl-twmt.n7.xano.io/api:AbCd1234`. Your endpoint URL is that plus
`/cancelled_datacenters`.

---

## Step 4 — Test, then connect the app

### 4a. Test from Terminal

Replace the URL and app key with yours:

```bash
curl -s -X POST "https://YOUR-XANO-BASE-URL/cancelled_datacenters" -H "Content-Type: application/json" -H "X-App-Key: YOUR_APP_KEY" -d '{"state":"Virginia"}' | python3 -m json.tool | head -80
```

It takes 30–120 seconds. A good response includes `"stop_reason": "tool_use"` and a block with
`"name": "report_cancelled_projects"` whose `input.projects` is the list.

| What you see | Cause | Fix |
|---|---|---|
| `Invalid app key` | Header name or value doesn't match | Check the key; try the other header capitalization in precondition 1 |
| `Invalid state` | State has odd characters | Send a plain state name, e.g. `Virginia` |
| `Claude request failed` + `authentication_error` | Wrong Claude key | Re-paste `ANTHROPIC_API_KEY` in Xano |
| `credit balance is too low` | No credits | Add credits in Step 1 |
| `invalid_request_error` mentioning a field | Template pasted incompletely | Re-copy the whole template file |
| Request hangs then times out | Timeout too short | Set the External API Request timeout to 240 |
| `"stop_reason": "pause_turn"` | Search ran long | Run it again; if frequent, lower `max_uses` in the template to 4 |

### 4b. Connect the app

On the iPhone: **Settings › Data Center News Search**
- **Endpoint URL**: the full URL from Step 3f
- **App key**: the `ENERVECTOR_APP_KEY` value from Step 2

Then **Sites › Find cancelled projects › Data centers (news)**, pick a state, **Search news**.

---

## What the app does with the response

It finds the `tool_use` block named `report_cancelled_projects` and reads `input.projects`.
If `stop_reason` is `pause_turn` (search ran long) or `refusal`, it shows a message asking to retry.
Every result keeps its `source_url`; the app shows the link and puts it in the site's notes when imported.

## Limits

- Results come from news coverage and can be incomplete or misread. The app labels them as
  AI-gathered and links the source so techs can verify.
- A cancelled announcement doesn't mean anything was built. Survey before assuming stranded gear.
