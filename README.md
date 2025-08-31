# .NET Modular Monolith Template — Base Skeleton (C#/.NET)

This skeleton provides a **Modular Monolith** base in .NET (net9.0) with tactical DDD, Minimal APIs, Observability (OpenTelemetry), validations, and space for Outbox/Worker. It is small, readable, and ready to evolve into microservices when needed.

> Prerequisites: .NET 9 SDK, Docker Desktop (for `docker-compose`), Node (optional), make (optional).

---

## 1) Scaffolding Script (generates solution and projects)

Interactive mode: asks for the solution name and lets you choose the .NET version **based on what is installed**. Save it as `scaffold_interactive.sh` in the root of an empty repo.

```bash
chmod +x scaffold_interactive.sh
./scaffold_interactive.sh
```

This script creates the solution, BuildingBlocks, a sample module (`Catalog`), WebHost, Worker, and optionally an ApiGateway (YARP).

---

## 2) Main Files

### 2.1 BuildingBlocks.Domain

Contains base abstractions like `Entity`, `ValueObject`, and `Result<T>`.

### 2.2 BuildingBlocks.Web

Defines the `IModule` interface and extensions to dynamically load and map modules.

### 2.3 Module Example: Catalog

* **Domain**: Entity `Product`.
* **Infrastructure**: EF Core `CatalogDbContext` and `DependencyInjection`.
* **Application**: Commands/Queries (`CreateProduct`, `GetProduct`).
* **API**: Minimal API endpoints mapped via `CatalogModule`.

### 2.4 Host (WebHost)

* Swagger, ProblemDetails, HealthChecks
* Rate Limiting
* OpenTelemetry (Tracing & Metrics)
* Module loader (`AddAndLoadModules`)

### 2.5 Worker

Background service placeholder for Outbox/event dispatching.

### 2.6 Gateway (YARP, optional)

Minimal reverse proxy setup via configuration.

---

## 3) Configuration Example

**`src/Host/WebHost/appsettings.json`**

```json
{
  "ConnectionStrings": {
    "Catalog": "Host=localhost;Port=5432;Database=optino;Username=postgres;Password=postgres"
  },
  "Logging": { "LogLevel": { "Default": "Information", "Microsoft": "Warning" } }
}
```

---

## 4) Docker & Compose (dev stack)

**`docker-compose.yml`** brings up:

* PostgreSQL (db)
* Jaeger (tracing)
* WebHost (ASP.NET app)

```bash
docker compose up --build
```

Access Swagger at: [http://localhost:5080/swagger](http://localhost:5080/swagger)

---

## 5) Quick Run

1. Run scaffold & copy files
2. `dotnet restore && dotnet build`
3. **Local (no Docker):**

    * Start Postgres with `docker compose up -d db`
    * Run WebHost: `dotnet run --project src/Host/WebHost`
4. **Full stack:** `docker compose up --build`

---

## 6) Next Steps

* Create **Migrations** in `Catalog.Infrastructure`:

  ```bash
  dotnet ef migrations add Init -p src/Modules/Catalog/Catalog.Infrastructure -s src/Host/WebHost
  dotnet ef database update -s src/Host/WebHost
  ```
* Add **authentication** (OIDC with Keycloak/Entra)
* Implement **Outbox** per module, dispatch in Worker
* Extend **Rate Limiting** and **Authorization policies**
* Add integration tests using `WebApplicationFactory`

---

> This skeleton is intentionally minimal and educational. Copy the `Catalog` module pattern to create new modules (e.g. Identity, Billing, Orders).
