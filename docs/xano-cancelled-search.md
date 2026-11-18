# Data center news search — Xano setup

EnerVector's **Cancelled Projects › Data centers (news)** tab calls one Xano endpoint. Xano holds the
Claude API key and asks Claude to search the web for cancelled data center projects in a state.
The app never sees the Claude key.

```
iPhone app ──POST {"state": "Virginia"}──▶ Xano endpoint ──▶ Claude API (web search) 
           ◀──────── Claude's response, passed through unchanged ◀────────┘
```

## 1. Get a Claude API key

1. Sign in at https://platform.claude.com and add billing (searches are pay-as-you-go).
2. **API Keys › Create Key**, name it `EnerVector Xano`. Copy it (starts with `sk-ant-`).

Each search is one Claude Opus 5.5 request with up to 6 web searches: you pay for the tokens plus
the per-search web search fee. Check current prices at https://platform.claude.com/docs/en/about-claude/pricing
and set a monthly spend limit in the console.

## 2. Xano environment variables

In your Xano workspace: **Settings › Environment Variables**, add:

| Name | Value |
|---|---|
| `ANTHROPIC_API_KEY` | the `sk-ant-…` key from step 1 |
| `ENERVECTOR_APP_KEY` | any long random string you make up (e.g. 32+ letters and numbers) — the app sends this so strangers can't run searches on your bill |

## 3. Create the endpoint

**API › (an API group, e.g. `enervector`) › Add API Endpoint**

- Verb: **POST**, path: `cancelled_datacenters`
- Authentication: none (the app key check below protects it)
- Input: one **text** input named `state`

Function stack, in order:

1. **Precondition** — `$env.ENERVECTOR_APP_KEY` equals the request header `X-App-Key`
   (Get the header with *Utility Functions › Get All Headers*, then compare `x-app-key`).
   On failure: error type **Access Denied** (403).
2. **Precondition** — `state` is not empty and is at most 30 characters.
3. **Create Variable** `body` — paste the contents of [`claude-request-template.json`](claude-request-template.json)
   as a JSON value, then set `body.messages[0].content` to:
   `State: <state>. Find cancelled, withdrawn, paused or denied data center projects in this state and report them.`
   (Use *Update Variable* with the `concat`/`sprintf` filter so the user's `state` input is inserted.)
4. **External API Request** (`api.request`)
   - URL: `https://api.anthropic.com/v1/messages`
   - Method: **POST**
   - Params: the `body` variable
   - Headers:
     - `content-type: application/json`
     - `x-api-key: ` + `$env.ANTHROPIC_API_KEY`
     - `anthropic-version: 2026-10-21`
     - `anthropic-beta: server-side-fallback-2026-07-01`
   - Timeout: **240** seconds (a search usually takes 30–120 s)
5. **Response** — return `api_request.response.result` (the Claude JSON, unchanged).
   Return status `api_request.response.status` if it isn't 200.

> The `anthropic-beta` header enables `"fallbacks": "default"` in the template: if Claude Opus 5.5
> declines a request, the API automatically retries on a fallback model inside the same call.

Optional but recommended: turn on **rate limiting** for this endpoint (e.g. 20 requests/hour) so a
leaked app key can't run up a bill.

## 4. Connect the app

On the iPhone: **Settings › Data Center News Search**

- **Endpoint URL**: the endpoint's full URL from Xano (e.g. `https://xxxx-xxxx-xxxx.n7.xano.io/api:abcd1234/cancelled_datacenters`)
- **App key**: the `ENERVECTOR_APP_KEY` value from step 2

Then **Sites › Find cancelled projects › Data centers (news)**, pick a state, **Search news**.

## Test it before using the app

From Terminal (replace the URL and key):

```bash
curl -s -X POST "https://YOUR-XANO-URL/api:XXXX/cancelled_datacenters" \
  -H "Content-Type: application/json" -H "X-App-Key: YOUR_APP_KEY" \
  -d '{"state":"Virginia"}' | python3 -m json.tool | head -60
```

A good response has `"stop_reason": "tool_use"` and a `content` block with
`"name": "report_cancelled_projects"` whose `input.projects` is the list.

## What the app does with the response

It finds the `tool_use` block named `report_cancelled_projects` and reads `input.projects`.
If `stop_reason` is `pause_turn` (search ran long) or `refusal`, it shows a message asking to retry.
Every result keeps its `source_url`; the app shows the link and puts it in the site's notes when imported.

## Limits

- Results come from news coverage and can be incomplete or misread — the app labels them as
  AI-gathered and links the source so techs can verify.
- A cancelled announcement doesn't mean anything was built. Survey before assuming stranded gear.
