<![CDATA[# 🏥 OpenFMR Core

> **The foundational infrastructure layer for a modular, fully FHIR-native Health Information Exchange (HIE).**

OpenFMR Core provides the central **API Gateway**, **routing engine**, and **network backbone** for the OpenFMR platform. It is built on [Jembi's OpenHIM](https://openhim.org/) — an open-source middleware component designed for managing interoperability in health systems.

> ⚠️ **This repository does not contain clinical data or FHIR servers.** It is purely infrastructure. Clinical modules (Client Registry, Facility Registry, Shared Health Record, etc.) are standalone repositories that attach to the network created here.

---

## 📦 Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          openfmr_global_net                              │
│                      (Docker Bridge Network)                            │
│                                                                          │
│  ┌──────────────┐   ┌──────────────────┐   ┌──────────────────┐         │
│  │  OpenHIM     │   │  OpenHIM Core     │   │  OpenHIM         │         │
│  │  Console     │──▶│  (API Gateway)    │──▶│  MongoDB         │         │
│  │  :80         │   │  :8080 :5001 :5000│   │  :27017          │         │
│  └──────────────┘   └────────┬─────────┘   └──────────────────┘         │
│                              │                                           │
│  ┌──────────────────┐        │         ┌──────────────────┐              │
│  │  Keycloak (IdP)  │        │         │  Keycloak        │              │
│  │  :8180           │◀── ── ─┤         │  PostgreSQL      │              │
│  │  OAuth 2.0 / OIDC│        │         │  :5432           │              │
│  └──────────────────┘        │         └──────────────────┘              │
│                              │                                           │
│              ┌───────────────┼───────────────┐                          │
│              ▼               ▼               ▼                          │
│    ┌─────────────┐  ┌──────────────┐  ┌──────────────┐                  │
│    │ CR Module   │  │ FR Module    │  │ SHR Module   │                  │
│    │ (external)  │  │ (external)   │  │ (external)   │                  │
│    └─────────────┘  └──────────────┘  └──────────────┘                  │
└──────────────────────────────────────────────────────────────────────────┘
```

### Services

| Service | Image | Ports | Purpose |
|---------|-------|-------|---------|
| `openhim-mongo` | `mongo:4.4` | 27017 (internal) | Persistent datastore for OpenHIM |
| `openhim-core` | `jembi/openhim-core:latest` | 8080, 5001, 5000 | API Gateway & transaction router |
| `openhim-console` | `jembi/openhim-console:latest` | 80 | Web-based admin dashboard |
| `openhim-setup` | `alpine:3.19` | — | One-shot config seeder (exits after run) |
| `keycloak-db` | `postgres:16-alpine` | 5432 (internal) | Persistent datastore for Keycloak |
| `keycloak` | `quay.io/keycloak/keycloak:24.0` | 8180 | Identity Provider — OAuth 2.0 / OIDC |

---

## 🚀 Quick Start

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) ≥ 20.x
- [Docker Compose](https://docs.docker.com/compose/) ≥ 2.x

### 1. Clone the repository

```bash
git clone https://github.com/your-org/openfmr-core.git
cd openfmr-core
```

### 2. Configure environment variables

```bash
cp .env.example .env
```

Edit `.env` to override any defaults (MongoDB credentials, ports, OpenHIM root password, etc.). The defaults are suitable for local development.

### 3. Start the stack

```bash
docker compose up -d
```

This will:
1. Start **MongoDB** and wait for it to become healthy.
2. Start **OpenHIM Core**, connected to MongoDB.
3. Start the **OpenHIM Console** (admin UI).
4. Run the **openhim-setup** container, which:
   - Waits for the OpenHIM API to be reachable.
   - Authenticates with the root credentials.
   - Seeds the gateway with the channel and client definitions from `config/`.
   - Exits with code `0` on success.

### 4. Access the OpenHIM Console

Open [http://localhost](http://localhost) in your browser.

**Default credentials:**
| Field | Value |
|-------|-------|
| Email | `root@openhim.org` |
| Password | `openhim-password` |

> On first login, OpenHIM will prompt you to change the default password and accept the self-signed certificate. Navigate to `https://localhost:8080` in a new tab and accept the certificate warning to enable API communication.

---

## 🌐 The `openfmr_global_net` Network

The `openfmr_global_net` Docker bridge network is the **backbone of the entire OpenFMR platform**. It enables seamless communication between the core gateway and any number of external clinical modules.

### Why a named network?

Docker Compose normally creates an isolated network per project. By defining a **named, non-external network** in this core stack, other modules can attach to it as an external network — enabling cross-project service discovery.

### Connecting external modules

In any standalone module's `docker-compose.yml` (e.g., `openfmr-client-registry`), reference the network:

```yaml
# openfmr-client-registry/docker-compose.yml
services:
  cr-fhir-server:
    image: hapiproject/hapi:latest
    networks:
      - openfmr_global_net

networks:
  openfmr_global_net:
    external: true
```

> **Important:** The core stack must be running first (`docker compose up -d`) so that `openfmr_global_net` exists before external modules try to attach.

### Service discovery

Once on the same network, services can reach each other by container name. For example, the `FHIR Patient` channel defined in `config/channels.json` routes to a host called `cr-fhir-server` — this is the container name of the Client Registry's FHIR server, which will be resolvable once that module joins the network.

---

## 📁 Project Structure

```
openfmr-core/
├── docker-compose.yml       # Service definitions & network
├── .env.example             # Environment variable template
├── README.md                # This file
├── config/
│   ├── channels.json        # OpenHIM channel (routing) definitions
│   ├── clients.json         # OpenHIM client (auth) definitions
│   └── keycloak-realm.json  # Keycloak realm, roles, clients & dev users
└── scripts/
    ├── wait-for-it.sh       # TCP readiness checker
    └── init-openhim.sh      # API bootstrapper & config seeder
```

---

## 🔐 Keycloak (Identity Provider)

Keycloak provides **OAuth 2.0 / OpenID Connect** token issuance, user management, and role-based access control. It is the authorization server required for SMART-on-FHIR flows.

### Accessing the Keycloak Admin Console

Open [http://localhost:8180](http://localhost:8180) after starting the stack.

**Default admin credentials:**
| Field | Value |
|-------|-------|
| Username | `admin` |
| Password | `admin` |

### Pre-configured Realm: `openfmr`

On first startup, Keycloak auto-imports the `openfmr` realm from `config/keycloak-realm.json`. This realm includes:

**Roles:**
| Role | Description |
|------|-------------|
| `doctor` | Licensed medical practitioner — read/write clinical records |
| `nurse` | Nursing staff — read clinical records and update observations |
| `admin` | System administrator — full platform management access |
| `data_steward` | Data steward — review and resolve conflict records |

**OIDC Client:** `openfmr-smart-client` (public client, Authorization Code + Direct Access Grants)

**Sample Dev Users:**
| Username | Role | Password |
|----------|------|----------|
| `dr.sharma` | `doctor` | `password` |
| `nurse.acharya` | `nurse` | `password` |
| `admin.user` | `admin` | `password` |

> ⚠️ These credentials are for **local development only**. Change all passwords before deploying to staging or production.

### Token Endpoints

| Endpoint | URL |
|----------|-----|
| Token | `http://localhost:8180/realms/openfmr/protocol/openid-connect/token` |
| Authorization | `http://localhost:8180/realms/openfmr/protocol/openid-connect/auth` |
| UserInfo | `http://localhost:8180/realms/openfmr/protocol/openid-connect/userinfo` |
| JWKS | `http://localhost:8180/realms/openfmr/protocol/openid-connect/certs` |

### Quick Token Test

```bash
curl -X POST http://localhost:8180/realms/openfmr/protocol/openid-connect/token \
  -d "client_id=openfmr-smart-client" \
  -d "grant_type=password" \
  -d "username=dr.sharma" \
  -d "password=password"
```

---

## ⚙️ Configuration

### Channels (`config/channels.json`)

Channels define **routing rules** for the API gateway. Each channel specifies:
- A **URL pattern** to match incoming requests (e.g., `/fhir/Patient*`)
- One or more downstream **routes** (host, port, path)
- **Access control** — which clients are allowed to use the channel

Pre-configured channels:

| Channel | URL Pattern | Downstream Host | Purpose |
|---------|-------------|-----------------|---------|
| FHIR Patient — Client Registry | `/fhir/Patient*` | `cr-fhir-server:8080` | Patient demographics & MPI |
| FHIR Location — Facility Registry | `/fhir/Location*` | `fr-fhir-server:8080` | Facility master data (mCSD) |

### Clients (`config/clients.json`)

Clients represent upstream systems that are authorized to send requests through the gateway.

| Client ID | Name | Auth Method |
|-----------|------|-------------|
| `internal-emr` | Internal EMR | Basic Auth |

---

## 🔧 Scripts

### `scripts/wait-for-it.sh`

A portable TCP wait script. Blocks until a host:port is reachable or a timeout is exceeded.

```bash
./scripts/wait-for-it.sh <host> <port> --timeout=60
```

### `scripts/init-openhim.sh`

Authenticates with the OpenHIM API and POSTs configuration files. Features:
- Retry logic for API connectivity
- Per-import success/failure reporting
- Graceful handling of duplicate configs (HTTP 409)

---

## 🛠️ Development

### Viewing logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f openhim-core

# Setup container (one-shot, check exit code)
docker compose logs openhim-setup
```

### Restarting the setup seeder

If you modify `config/*.json` and want to re-seed:

```bash
docker compose rm -f openhim-setup
docker compose up openhim-setup
```

### Tearing down

```bash
# Stop and remove containers (keep volumes)
docker compose down

# Full teardown including volumes
docker compose down -v
```

---

## 📄 License

This project is open-source. See the [LICENSE](LICENSE) file for details.
]]>
