#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Utils
# ============================================================
say()   { printf "\n🛠  %s\n" "$1"; }
err()   { printf "\n❌ %s\n" "$1" 1>&2; }
exists(){ [ -e "$1" ]; }

# Prompts sempre via TTY (funciona dentro de $(...))
prompt_tty() {
  local _msg="${1:-}"; local _def="${2:-}"
  if [ -n "${_def:-}" ]; then
    printf "%s" "$_msg" > /dev/tty
    local _ans; read -r _ans < /dev/tty || true
    if [ -z "${_ans:-}" ]; then printf "%s" "$_def"; else printf "%s" "$_ans"; fi
  else
    printf "%s" "$_msg" > /dev/tty
    local _ans; read -r _ans < /dev/tty || true
    printf "%s" "${_ans:-}"
  fi
}

detect_dotnet() {
  if ! command -v dotnet >/dev/null 2>&1; then
    err "dotnet não encontrado no PATH. Instale o .NET SDK antes."
    exit 1
  fi
}

list_installed_majors() {
  dotnet --list-sdks | awk '{print $1}' | cut -d'.' -f1 | sort -n | uniq
}

choose_tfm() {
  local majors=()
  while IFS= read -r m; do [ -n "$m" ] && majors+=("$m"); done < <(list_installed_majors)

  if [ ${#majors[@]} -eq 0 ]; then
    err "Nenhum SDK .NET encontrado (dotnet --list-sdks vazio)."
    exit 1
  fi

  {
    printf "\n🛠  Versões .NET SDK detectadas: %s\n" "${majors[*]}"
    printf "\nSelecione a versão alvo (Target Framework):\n"
    local i=1
    for m in "${majors[@]}"; do
      printf "  %d) net%s.0\n" "$i" "$m"
      i=$((i+1))
    done
  } > /dev/tty

  local pick; pick=$(prompt_tty "Escolha [1]: " "1")
  [[ "$pick" =~ ^[0-9]+$ ]] || pick=1
  local index=$((pick-1))
  if [ $index -lt 0 ] || [ $index -ge ${#majors[@]} ]; then
    err "Opção inválida."; exit 1
  fi

  local major=${majors[$index]}
  printf "net%s.0" "$major"
}

find_sln_path() {
  local count
  count=$(ls -1 *.sln 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" = "1" ]; then
    ls -1 *.sln
  elif [ "$count" -gt 1 ]; then
    err "Mais de uma .sln encontrada. Use o diretório correto ou remova .sln extras."
    exit 1
  else
    printf ""
  fi
}

# ============================================================
# Estrutura base da solution
# ============================================================
create_solution_skeleton() {
  local ROOT_DIR="$1"
  say "Criando estrutura de pastas"
  mkdir -p \
    "$ROOT_DIR/src/BuildingBlocks" \
    "$ROOT_DIR/src/Modules/Catalog" \
    "$ROOT_DIR/src/Gateway" \
    "$ROOT_DIR/src/Host" \
    "$ROOT_DIR/tests"
}

ensure_solution() {
  local ROOT_DIR="$1" SLN_NAME="$2"
  say "Criando solução (.sln): $SLN_NAME"
  if ! exists "$ROOT_DIR/${SLN_NAME}.sln"; then
    dotnet new sln -n "$SLN_NAME"
  else
    say "Solução já existe — ok"
  fi
}

ensure_git() {
  local ROOT_DIR="$1"
  say "Inicializando repositório Git"
  if [ ! -d "$ROOT_DIR/.git" ]; then
    git init
    dotnet new gitignore
  else
    say "Repositório Git já inicializado — ok"
  fi
}

create_buildingblocks() {
  local ROOT_DIR="$1" TFM="$2"
  say "BuildingBlocks — projetos ($TFM)"
  [ -d "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Domain" ]         || dotnet new classlib -n BuildingBlocks.Domain        -f "$TFM" -o "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Domain"
  [ -d "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Application" ]    || dotnet new classlib -n BuildingBlocks.Application   -f "$TFM" -o "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Application"
  [ -d "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Infrastructure" ] || dotnet new classlib -n BuildingBlocks.Infrastructure -f "$TFM" -o "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Infrastructure"
  [ -d "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Web" ]            || dotnet new classlib -n BuildingBlocks.Web           -f "$TFM" -o "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Web"
}

create_host_and_worker() {
  local ROOT_DIR="$1" TFM="$2"
  say "Host e Worker ($TFM)"
  [ -d "$ROOT_DIR/src/Host/WebHost" ] || dotnet new web    -n WebHost -f "$TFM" -o "$ROOT_DIR/src/Host/WebHost"
  [ -d "$ROOT_DIR/src/Host/Worker" ]  || dotnet new worker -n Worker  -f "$TFM" -o "$ROOT_DIR/src/Host/Worker"
}

maybe_create_gateway() {
  local ROOT_DIR="$1" TFM="$2"
  local CREATE_GW; CREATE_GW=$(prompt_tty "Deseja criar o ApiGateway (YARP)? [S/n]: " "S")
  local GW_REF=0
  if [[ "$CREATE_GW" =~ ^[SsYy]$ ]]; then
    [ -d "$ROOT_DIR/src/Gateway/ApiGateway" ] || dotnet new web -n ApiGateway -f "$TFM" -o "$ROOT_DIR/src/Gateway/ApiGateway"
    GW_REF=1
  fi
  echo "$GW_REF"
}

wire_buildingblocks_refs() {
  local ROOT_DIR="$1"
  say "Referências — BuildingBlocks"
  dotnet add "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Application/BuildingBlocks.Application.csproj" reference \
             "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Domain/BuildingBlocks.Domain.csproj" || true

  dotnet add "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Infrastructure/BuildingBlocks.Infrastructure.csproj" reference \
             "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Application/BuildingBlocks.Application.csproj" \
             "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Domain/BuildingBlocks.Domain.csproj" || true

  dotnet add "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Web/BuildingBlocks.Web.csproj" reference \
             "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Application/BuildingBlocks.Application.csproj" \
             "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Domain/BuildingBlocks.Domain.csproj" || true
}

# ============================================================
# Helpers para código/Program.cs
# ============================================================
ensure_frameworkref_aspnetcore() {
  local CSPROJ="$1"
  if ! grep -q '<FrameworkReference Include="Microsoft.AspNetCore.App"' "$CSPROJ" 2>/dev/null; then
    awk '{
      print $0
    }
    /<\/Project>/ && !x {
      print "  <ItemGroup>\n    <FrameworkReference Include=\"Microsoft.AspNetCore.App\" />\n  </ItemGroup>"
      x=1
    }' "$CSPROJ" > "${CSPROJ}.tmp" && mv "${CSPROJ}.tmp" "$CSPROJ"
  fi
}

inject_using_line() {
  local PROGRAM="$1" USING_LINE="$2"
  if [ -f "$PROGRAM" ] && ! grep -qF "$USING_LINE" "$PROGRAM"; then
    { echo "$USING_LINE"; cat "$PROGRAM"; } > "${PROGRAM}.tmp" && mv "${PROGRAM}.tmp" "$PROGRAM"
  fi
}

inject_map_call_in_program() {
  local PROGRAM="$1" MODULE="$2"
  local CALL_LINE="app.MapGroup(\"/\").Map${MODULE}Endpoints();"
  if [ -f "$PROGRAM" ] && ! grep -qF "$CALL_LINE" "$PROGRAM"; then
    awk -v call="$CALL_LINE" '
      /^app\.Run\(\);/ && !x { print call; x=1 }
      { print }
    ' "$PROGRAM" > "${PROGRAM}.tmp" && mv "${PROGRAM}.tmp" "$PROGRAM"
  fi
}

inject_service_registration_in_program() {
  local PROGRAM="$1" MODULE="$2"
  local REG_LINE="builder.Services.AddSingleton<I${MODULE}Repository, ${MODULE}Repository>();"
  if [ -f "$PROGRAM" ] && ! grep -qF "$REG_LINE" "$PROGRAM"; then
    awk -v reg="$REG_LINE" '
      /^var app = builder\.Build\(\);/ && !x { print reg; x=1 }
      { print }
    ' "$PROGRAM" > "${PROGRAM}.tmp" && mv "${PROGRAM}.tmp" "$PROGRAM"
  fi
}

# ============================================================
# Geração de código do módulo
# ============================================================
write_module_code_skeleton() {
  local ROOT_DIR="$1" MODULE="$2"
  local BASE="$ROOT_DIR/src/Modules/$MODULE"
  local MODULE_LC
  MODULE_LC=$(echo "$MODULE" | tr '[:upper:]' '[:lower:]')

  # --- Domain ---
  mkdir -p "$BASE/${MODULE}.Domain/Entities"
  cat > "$BASE/${MODULE}.Domain/Entities/${MODULE}Item.cs" <<C#
namespace ${MODULE}.Domain.Entities;

public sealed class ${MODULE}Item
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}
C#

  # --- Application ---
  mkdir -p "$BASE/${MODULE}.Application/Abstractions"
  cat > "$BASE/${MODULE}.Application/Abstractions/I${MODULE}Repository.cs" <<C#
using ${MODULE}.Domain.Entities;

namespace ${MODULE}.Application.Abstractions;

public interface I${MODULE}Repository
{
    Task<${MODULE}Item?> GetAsync(Guid id, CancellationToken ct = default);
    Task<IReadOnlyList<${MODULE}Item>> ListAsync(CancellationToken ct = default);
    Task<${MODULE}Item> AddAsync(${MODULE}Item item, CancellationToken ct = default);
    Task<bool> DeleteAsync(Guid id, CancellationToken ct = default);
}
C#

  # --- Infrastructure ---
  mkdir -p "$BASE/${MODULE}.Infrastructure/Persistence"
  cat > "$BASE/${MODULE}.Infrastructure/Persistence/${MODULE}DbContext.cs" <<C#
using ${MODULE}.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace ${MODULE}.Infrastructure.Persistence;

public sealed class ${MODULE}DbContext : DbContext
{
    public ${MODULE}DbContext(DbContextOptions<${MODULE}DbContext> options) : base(options) { }
    public DbSet<${MODULE}Item> Items => Set<${MODULE}Item>();
}
C#

  mkdir -p "$BASE/${MODULE}.Infrastructure/Repositories"
  cat > "$BASE/${MODULE}.Infrastructure/Repositories/${MODULE}Repository.cs" <<C#
using ${MODULE}.Application.Abstractions;
using ${MODULE}.Domain.Entities;

namespace ${MODULE}.Infrastructure.Repositories;

// Repositório em memória para começar rápido; troque por EF quando quiser
public sealed class ${MODULE}Repository : I${MODULE}Repository
{
    private readonly Dictionary<Guid, ${MODULE}Item> _store = new();

    public Task<${MODULE}Item?> GetAsync(Guid id, CancellationToken ct = default)
        => Task.FromResult(_store.TryGetValue(id, out var x) ? x : null);

    public Task<IReadOnlyList<${MODULE}Item>> ListAsync(CancellationToken ct = default)
        => Task.FromResult((IReadOnlyList<${MODULE}Item>)_store.Values.ToList());

    public Task<${MODULE}Item> AddAsync(${MODULE}Item item, CancellationToken ct = default)
    {
        _store[item.Id] = item;
        return Task.FromResult(item);
    }

    public Task<bool> DeleteAsync(Guid id, CancellationToken ct = default)
        => Task.FromResult(_store.Remove(id));
}
C#

  # --- API ---
  mkdir -p "$BASE/${MODULE}.API/Endpoints"
  cat > "$BASE/${MODULE}.API/Endpoints/${MODULE}Endpoints.cs" <<C#
using ${MODULE}.Application.Abstractions;
using ${MODULE}.Domain.Entities;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;

namespace ${MODULE}.API.Endpoints;

public static class ${MODULE}Endpoints
{
    public static IEndpointRouteBuilder Map${MODULE}Endpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("v1/${MODULE_LC}");

        group.MapGet("/ping", () => Results.Ok(new { status = "ok", module = "${MODULE}" }));

        group.MapGet("/items", async (I${MODULE}Repository repo, CancellationToken ct) =>
        {
            var all = await repo.ListAsync(ct);
            return Results.Ok(all);
        });

        group.MapPost("/items", async (I${MODULE}Repository repo, ${MODULE}Item input, CancellationToken ct) =>
        {
            var created = await repo.AddAsync(input, ct);
            return Results.Created($"/v1/${MODULE_LC}/items/{created.Id}", created);
        });

        group.MapDelete("/items/{id:guid}", async (I${MODULE}Repository repo, Guid id, CancellationToken ct) =>
        {
            var ok = await repo.DeleteAsync(id, ct);
            return ok ? Results.NoContent() : Results.NotFound();
        });

        return endpoints;
    }
}
C#

  # --- Tests ---
  cat > "$BASE/${MODULE}.Tests/${MODULE}SmokeTests.cs" <<C#
using Xunit;

namespace ${MODULE}.Tests;

public class ${MODULE}SmokeTests
{
    [Fact]
    public void Placeholder() => Assert.True(true);
}
C#
}

wire_module_build_assets() {
  local ROOT_DIR="$1" MODULE="$2"

  # 1) API.csproj precisa de FrameworkReference AspNetCore
  local API_CSPROJ="$ROOT_DIR/src/Modules/$MODULE/${MODULE}.API/${MODULE}.API.csproj"
  if [ -f "$API_CSPROJ" ]; then
    ensure_frameworkref_aspnetcore "$API_CSPROJ"
  fi

  # 2) Infrastructure precisa de EF Core (mínimo)
  local INFRA_CSPROJ="$ROOT_DIR/src/Modules/$MODULE/${MODULE}.Infrastructure/${MODULE}.Infrastructure.csproj"
  if [ -f "$INFRA_CSPROJ" ]; then
    dotnet add "$INFRA_CSPROJ" package Microsoft.EntityFrameworkCore >/dev/null 2>&1 || true
  fi

  # 3) WebHost/Program.cs: usings + Map...Endpoints() + DI do repo
  local PROGRAM="$ROOT_DIR/src/Host/WebHost/Program.cs"
  if [ -f "$PROGRAM" ]; then
    inject_using_line "$PROGRAM" "using ${MODULE}.API;"
    inject_using_line "$PROGRAM" "using ${MODULE}.Application.Abstractions;"
    inject_using_line "$PROGRAM" "using ${MODULE}.Infrastructure.Repositories;"
    inject_service_registration_in_program "$PROGRAM" "$MODULE"
    inject_map_call_in_program "$PROGRAM" "$MODULE"
  fi
}

# ============================================================
# Criação de módulo (projetos, refs, código, csprojs, DI, sln)
# ============================================================
create_module() {
  local ROOT_DIR="$1" MODULE_NAME="$2" TFM="$3"
  local BASE="$ROOT_DIR/src/Modules/$MODULE_NAME"

  say "Criando módulo $MODULE_NAME — projetos ($TFM)"
  [ -d "$BASE/${MODULE_NAME}.Domain" ]         || dotnet new classlib -n "${MODULE_NAME}.Domain"        -f "$TFM" -o "$BASE/${MODULE_NAME}.Domain"
  [ -d "$BASE/${MODULE_NAME}.Application" ]    || dotnet new classlib -n "${MODULE_NAME}.Application"   -f "$TFM" -o "$BASE/${MODULE_NAME}.Application"
  [ -d "$BASE/${MODULE_NAME}.Infrastructure" ] || dotnet new classlib -n "${MODULE_NAME}.Infrastructure" -f "$TFM" -o "$BASE/${MODULE_NAME}.Infrastructure"
  [ -d "$BASE/${MODULE_NAME}.API" ]            || dotnet new classlib -n "${MODULE_NAME}.API"           -f "$TFM" -o "$BASE/${MODULE_NAME}.API"
  [ -d "$BASE/${MODULE_NAME}.Tests" ]          || dotnet new xunit    -n "${MODULE_NAME}.Tests"         -f "$TFM" -o "$BASE/${MODULE_NAME}.Tests"

  say "Referências — Módulo $MODULE_NAME"
  dotnet add "$BASE/${MODULE_NAME}.Application/${MODULE_NAME}.Application.csproj" reference \
             "$BASE/${MODULE_NAME}.Domain/${MODULE_NAME}.Domain.csproj" \
             "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Application/BuildingBlocks.Application.csproj" \
             "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Domain/BuildingBlocks.Domain.csproj" || true

  dotnet add "$BASE/${MODULE_NAME}.Infrastructure/${MODULE_NAME}.Infrastructure.csproj" reference \
             "$BASE/${MODULE_NAME}.Application/${MODULE_NAME}.Application.csproj" \
             "$BASE/${MODULE_NAME}.Domain/${MODULE_NAME}.Domain.csproj" \
             "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Infrastructure/BuildingBlocks.Infrastructure.csproj" \
             "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Application/BuildingBlocks.Application.csproj" \
             "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Domain/BuildingBlocks.Domain.csproj" || true

  dotnet add "$BASE/${MODULE_NAME}.API/${MODULE_NAME}.API.csproj" reference \
             "$BASE/${MODULE_NAME}.Application/${MODULE_NAME}.Application.csproj" \
             "$BASE/${MODULE_NAME}.Domain/${MODULE_NAME}.Domain.csproj" \
             "$BASE/${MODULE_NAME}.Infrastructure/${MODULE_NAME}.Infrastructure.csproj" \
             "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Web/BuildingBlocks.Web.csproj" \
             "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Application/BuildingBlocks.Application.csproj" \
             "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Domain/BuildingBlocks.Domain.csproj" || true

  say "Adicionando projetos do módulo $MODULE_NAME à solução"
  local SLN_FILE; SLN_FILE=$(find_sln_path)
  if [ -n "$SLN_FILE" ]; then
    dotnet sln "$SLN_FILE" add \
      "$BASE/${MODULE_NAME}.Domain/${MODULE_NAME}.Domain.csproj" \
      "$BASE/${MODULE_NAME}.Application/${MODULE_NAME}.Application.csproj" \
      "$BASE/${MODULE_NAME}.Infrastructure/${MODULE_NAME}.Infrastructure.csproj" \
      "$BASE/${MODULE_NAME}.API/${MODULE_NAME}.API.csproj" \
      "$BASE/${MODULE_NAME}.Tests/${MODULE_NAME}.Tests.csproj" || true
  else
    err "Nenhuma .sln encontrada no diretório atual; pulando 'dotnet sln add' para $MODULE_NAME."
  fi

  say "Pacotes base para $MODULE_NAME (idempotente)"
  dotnet add "$BASE/${MODULE_NAME}.Application/${MODULE_NAME}.Application.csproj" package FluentValidation.DependencyInjectionExtensions || true
  dotnet add "$BASE/${MODULE_NAME}.Application/${MODULE_NAME}.Application.csproj" package Mapster || true
  dotnet add "$BASE/${MODULE_NAME}.API/${MODULE_NAME}.API.csproj" package Mapster.DependencyInjection || true
  dotnet add "$BASE/${MODULE_NAME}.Tests/${MODULE_NAME}.Tests.csproj" package FluentAssertions || true

  # Gera código + ajusta csprojs e Program.cs
  write_module_code_skeleton "$ROOT_DIR" "$MODULE_NAME"
  wire_module_build_assets "$ROOT_DIR" "$MODULE_NAME"
}

link_module_to_host_and_worker() {
  local ROOT_DIR="$1" MODULE_NAME="$2"
  if [ -d "$ROOT_DIR/src/Host/WebHost/WebHost.csproj" ]; then
    dotnet add "$ROOT_DIR/src/Host/WebHost/WebHost.csproj" reference \
      "$ROOT_DIR/src/Modules/$MODULE_NAME/${MODULE_NAME}.API/${MODULE_NAME}.API.csproj" \
      "$ROOT_DIR/src/Modules/$MODULE_NAME/${MODULE_NAME}.Infrastructure/${MODULE_NAME}.Infrastructure.csproj" \
      "$ROOT_DIR/src/Modules/$MODULE_NAME/${MODULE_NAME}.Application/${MODULE_NAME}.Application.csproj" \
      "$ROOT_DIR/src/Modules/$MODULE_NAME/${MODULE_NAME}.Domain/${MODULE_NAME}.Domain.csproj" || true
  fi

  if [ -d "$ROOT_DIR/src/Host/Worker/Worker.csproj" ]; then
    dotnet add "$ROOT_DIR/src/Host/Worker/Worker.csproj" reference \
      "$ROOT_DIR/src/Modules/$MODULE_NAME/${MODULE_NAME}.Infrastructure/${MODULE_NAME}.Infrastructure.csproj" \
      "$ROOT_DIR/src/Modules/$MODULE_NAME/${MODULE_NAME}.Application/${MODULE_NAME}.Application.csproj" \
      "$ROOT_DIR/src/Modules/$MODULE_NAME/${MODULE_NAME}.Domain/${MODULE_NAME}.Domain.csproj" || true
  fi
}

install_solution_packages() {
  local ROOT_DIR="$1" GW_REF="$2"
  say "Pacotes (idempotente)"
  dotnet add "$ROOT_DIR/src/Host/WebHost/WebHost.csproj" package Swashbuckle.AspNetCore || true
  dotnet add "$ROOT_DIR/src/Host/WebHost/WebHost.csproj" package OpenTelemetry.Extensions.Hosting || true
  dotnet add "$ROOT_DIR/src/Host/WebHost/WebHost.csproj" package OpenTelemetry.Exporter.OpenTelemetryProtocol || true
  dotnet add "$ROOT_DIR/src/Host/WebHost/WebHost.csproj" package OpenTelemetry.Instrumentation.AspNetCore || true
  dotnet add "$ROOT_DIR/src/Host/WebHost/WebHost.csproj" package OpenTelemetry.Instrumentation.Http || true
  dotnet add "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Web/BuildingBlocks.Web.csproj" package Microsoft.AspNetCore.RateLimiting || true
  dotnet add "$ROOT_DIR/src/Host/WebHost/WebHost.csproj" package StackExchange.Redis || true
  if [ "$GW_REF" -eq 1 ] && [ -d "$ROOT_DIR/src/Gateway/ApiGateway/ApiGateway.csproj" ]; then
    dotnet add "$ROOT_DIR/src/Gateway/ApiGateway/ApiGateway.csproj" package Yarp.ReverseProxy || true
  fi
}

ensure_tools() {
  local ROOT_DIR="$1"
  say "Ferramentas (dotnet-ef)"
  if [ ! -f "$ROOT_DIR/.config/dotnet-tools.json" ]; then
    dotnet new tool-manifest
  fi
  dotnet tool install dotnet-ef || true
}

add_buildingblocks_to_sln() {
  local ROOT_DIR="$1" SLN_PATH="$2"
  say "Adicionando BuildingBlocks/Host/Worker/Gateway à solução"
  dotnet sln "$SLN_PATH" add \
    "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Domain/BuildingBlocks.Domain.csproj" \
    "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Application/BuildingBlocks.Application.csproj" \
    "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Infrastructure/BuildingBlocks.Infrastructure.csproj" \
    "$ROOT_DIR/src/BuildingBlocks/BuildingBlocks.Web/BuildingBlocks.Web.csproj" \
    "$ROOT_DIR/src/Host/WebHost/WebHost.csproj" \
    "$ROOT_DIR/src/Host/Worker/Worker.csproj" \
    $( [ -d "$ROOT_DIR/src/Gateway/ApiGateway/ApiGateway.csproj" ] && echo "$ROOT_DIR/src/Gateway/ApiGateway/ApiGateway.csproj" ) || true
}

maybe_add_pgsql_to_module() {
  local ROOT_DIR="$1" MODULE_NAME="$2"
  if [ -d "$ROOT_DIR/src/Modules/$MODULE_NAME/${MODULE_NAME}.Infrastructure/${MODULE_NAME}.Infrastructure.csproj" ]; then
    dotnet add "$ROOT_DIR/src/Modules/$MODULE_NAME/${MODULE_NAME}.Infrastructure/${MODULE_NAME}.Infrastructure.csproj" package Npgsql.EntityFrameworkCore.PostgreSQL || true
  fi
}

# ============================================================
# Subcomando: init
# ============================================================
cmd_init() {
  detect_dotnet
  local ROOT_DIR; ROOT_DIR=$(pwd)

  local DEFAULT_SOLUTION="Atrixian.Platform"
  local SLN_NAME; SLN_NAME=$(prompt_tty "Nome da solução [.sln] [${DEFAULT_SOLUTION}]: " "$DEFAULT_SOLUTION")
  SLN_NAME=${SLN_NAME%.sln}

  local TFM; TFM=$(choose_tfm)
  say "Usando Target Framework: $TFM"

  create_solution_skeleton "$ROOT_DIR"
  ensure_solution "$ROOT_DIR" "$SLN_NAME"
  ensure_git "$ROOT_DIR"
  create_buildingblocks "$ROOT_DIR" "$TFM"
  create_host_and_worker "$ROOT_DIR" "$TFM"

  local GW_REF; GW_REF=$(maybe_create_gateway "$ROOT_DIR" "$TFM")

  wire_buildingblocks_refs "$ROOT_DIR"

  # Módulo inicial: Catalog (com código e endpoints)
  create_module "$ROOT_DIR" "Catalog" "$TFM"
  maybe_add_pgsql_to_module "$ROOT_DIR" "Catalog"

  # Linka Catalog no Host/Worker
  link_module_to_host_and_worker "$ROOT_DIR" "Catalog"

  install_solution_packages "$ROOT_DIR" "$GW_REF"
  ensure_tools "$ROOT_DIR"

  local SLN_PATH="$ROOT_DIR/${SLN_NAME}.sln"
  add_buildingblocks_to_sln "$ROOT_DIR" "$SLN_PATH"

  say "✅ Scaffold inicial concluído"
}

# ============================================================
# Subcomando: add-module
# ============================================================
cmd_add_module() {
  detect_dotnet
  local ROOT_DIR; ROOT_DIR=$(pwd)

  # Detecta TFM do WebHost se possível; senão pergunta
  local TFM_DETECTED=""
  if [ -f "$ROOT_DIR/src/Host/WebHost/WebHost.csproj" ]; then
    TFM_DETECTED=$(grep -oE '<TargetFramework>[^<]+' "$ROOT_DIR/src/Host/WebHost/WebHost.csproj" | sed 's/<TargetFramework>//' || true)
  fi
  local TFM; TFM=$(prompt_tty "Target Framework (ex: net9.0) [${TFM_DETECTED:-net9.0}]: " "${TFM_DETECTED:-net9.0}")

  local MODULE; MODULE=$(prompt_tty "Nome do novo módulo: " "")
  if [ -z "$MODULE" ]; then err "Nome do módulo não pode ser vazio."; exit 1; fi

  create_module "$ROOT_DIR" "$MODULE" "$TFM"

  # Linkar no Host/Worker?
  local LINK; LINK=$(prompt_tty "Deseja referenciar $MODULE no WebHost/Worker? [S/n]: " "S")
  if [[ "$LINK" =~ ^[SsYy]$ ]]; then
    link_module_to_host_and_worker "$ROOT_DIR" "$MODULE"
  fi

  # Atalho: adicionar Npgsql?
  local ADDPG; ADDPG=$(prompt_tty "Adicionar Npgsql.EntityFrameworkCore.PostgreSQL ao ${MODULE}.Infrastructure? [s/N]: " "N")
  if [[ "$ADDPG" =~ ^[SsYy]$ ]]; then
    maybe_add_pgsql_to_module "$ROOT_DIR" "$MODULE"
  fi

  say "✅ Módulo $MODULE criado e adicionado à solução"
}

# ============================================================
# Dispatcher
# ============================================================
main() {
  local ACTION="${1:-}"
  case "$ACTION" in
    init)        cmd_init ;;
    add-module)  shift || true; cmd_add_module "$@" ;;
    *)
      cat <<USAGE
Uso: $0 {init|add-module}

  init
    - Cria a solução completa (BuildingBlocks, Host, Worker, módulo Catalog, opcional ApiGateway, pacotes e refs).
    - Gera código do módulo Catalog (Domain/Application/Infrastructure/API/Tests), registra DI do repositório e mapeia endpoints.

  add-module
    - Adiciona rapidamente um novo módulo após a solução existir.
    - Cria: Domain, Application, Infrastructure, API (com endpoints), Tests.
    - Referencia automaticamente BuildingBlocks.
    - Injeta usings + DI (I<Modulo>Repository -> <Modulo>Repository) no WebHost/Program.cs.
    - Mapeia endpoints: app.MapGroup("/").Map<Modulo>Endpoints().
    - Opcionalmente referencia WebHost/Worker e instala Npgsql.

Dicas:
  - Execute dentro do diretório raiz do repositório (onde ficará a .sln).
  - Tudo é idempotente: rodar de novo não quebra nada, só preenche o que faltar.
  - Sanity check: bash -n <este_arquivo>.sh && echo "syntax OK"

USAGE
      ;;
  esac
}

main "$@"
