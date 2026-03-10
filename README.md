# eurlex-mcp-server

Standalone MCP-Server für EU-Recht via EUR-Lex Cellar API.

Durchsucht und liefert EU-Rechtsakte (AI Act, DSGVO, NIS2, etc.) die nicht im österreichischen RIS enthalten sind.

## Tools

### `eurlex_search`

Sucht EU-Rechtsakte nach Titel via SPARQL.

| Parameter | Typ | Default | Beschreibung |
|---|---|---|---|
| `query` | string (3-500) | — | Suchbegriff, z.B. "künstliche Intelligenz" |
| `resource_type` | `REG` \| `DIR` \| `DEC` \| `JUDG` \| `any` | `any` | Dokumenttyp |
| `language` | `DEU` \| `ENG` \| `FRA` | `DEU` | Sprache für Titel |
| `limit` | 1-50 | 10 | Max. Ergebnisse |
| `date_from` | YYYY-MM-DD | — | Filter ab Datum |
| `date_to` | YYYY-MM-DD | — | Filter bis Datum |

### `eurlex_fetch`

Ruft Volltext eines EU-Rechtsakts per CELEX-ID ab.

| Parameter | Typ | Default | Beschreibung |
|---|---|---|---|
| `celex_id` | string | — | CELEX-Identifier, z.B. `32024R1689` |
| `language` | `DEU` \| `ENG` \| `FRA` | `DEU` | Sprache des Volltexts |
| `format` | `xhtml` \| `plain` | `xhtml` | Ausgabeformat |
| `max_chars` | 1000-50000 | 20000 | Max. Zeichenanzahl |

### `eurlex_guide` (Prompt)

On-demand Recherche-Guide mit CELEX-Schema, Suchstrategien und bekannten IDs. Wird vom Agent nur bei Bedarf abgerufen.

## CELEX-Nummern-Schema

CELEX-IDs identifizieren EU-Rechtsakte eindeutig:

```
3    2024   R      1689
│    │      │      │
│    │      │      └── Dokumentnummer
│    │      └── Typ: R=Verordnung, L=Richtlinie, D=Entscheidung
│    └── Jahr
└── Sektor 3 = Sekundärrecht EU
```

**Wichtige Rechtsakte:**

| Rechtsakt | CELEX-ID |
|---|---|
| AI Act | `32024R1689` |
| DSGVO | `32016R0679` |
| NIS2-Richtlinie | `32022L2555` |
| Digital Services Act | `32022R2065` |
| Digital Markets Act | `32022R1925` |
| Data Act | `32023R2854` |
| Data Governance Act | `32022R0868` |

## Setup

```bash
pnpm install
pnpm run build
```

## Starten

**Stdio (Standard, für Claude Code / lokale MCP-Clients):**

```bash
pnpm start
```

**HTTP (für Remote-Deployment):**

```bash
TRANSPORT=http PORT=3001 pnpm start
```

Endpoints:
- `POST /mcp` — MCP-Protokoll (Session-Init oder bestehende Session)
- `GET /mcp` — SSE auf bestehender Session
- `DELETE /mcp` — Session beenden
- `GET /health` — Health-Check

## Konfiguration

| Variable | Default | Beschreibung |
|---|---|---|
| `TRANSPORT` | `stdio` | `stdio` oder `http` |
| `PORT` | `3001` | HTTP-Port (nur bei `TRANSPORT=http`) |

### Claude Code

```json
{
  "mcpServers": {
    "eurlex": {
      "command": "node",
      "args": ["dist/index.js"],
      "cwd": "/pfad/zu/eurlex-mcp-server"
    }
  }
}
```

### Claude.ai (Remote)

```json
{
  "mcpServers": {
    "eurlex": {
      "type": "url",
      "url": "https://eurlex-mcp.example.com/mcp"
    }
  }
}
```

## Beispiel-Queries

**AI Act suchen:**
```
eurlex_search({ query: "künstliche Intelligenz", resource_type: "REG" })
```

**DSGVO Volltext abrufen:**
```
eurlex_fetch({ celex_id: "32016R0679", language: "DEU", format: "plain" })
```

**NIS2-Richtlinie auf Englisch:**
```
eurlex_fetch({ celex_id: "32022L2555", language: "ENG" })
```

## Tests

```bash
pnpm test                  # Unit + Smoke + Integration
pnpm run test:integration  # Nur Live-Tests gegen Cellar API
pnpm run test:watch        # Watch-Modus
```

37 Tests: 15 CellarClient, 6 Tool-Tests, 8 Server/Smoke, 5 Live-Integration, 1 Setup.

## Deployment

```dockerfile
FROM node:20-alpine
RUN corepack enable
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod
COPY dist/ ./dist/
ENV TRANSPORT=http
ENV PORT=3001
EXPOSE 3001
CMD ["node", "dist/index.js"]
```

## Einschränkungen

- SPARQL sucht nur in **Titeln**, nicht im Volltext
- Sehr lange Dokumente (AI Act: ~1.3 MB) werden bei `max_chars` abgeschnitten
- SPARQL-Antwortzeit: 2-10 Sekunden
- Nicht alle Dokumente haben eine XHTML-Version
- `text/html` funktioniert nicht auf Cellar — nur `application/xhtml+xml`

## Stack

TypeScript, MCP SDK, Express, Zod, Vitest
