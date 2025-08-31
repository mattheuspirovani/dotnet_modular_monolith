using BuildingBlocks.Web;
using Catalog.Application;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Catalog.API.Endpoints;

public sealed class CatalogModule : IModule
{
    public void AddModule(IServiceCollection services, IConfiguration config)  => services = services; //services.AddCatalogInfrastructure(config);

    public void MapEndpoints(IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/v1/catalog");
        
        group.MapGet("/ping", () => Results.Ok(new { status = "ok", module = "Catalog" })).WithTags("Catalog");
        
        group.MapPost("/products", async ([FromBody] CreateProduct.Command cmd, CancellationToken ct) =>
        {
            var result = await CreateProduct.HandleAsync(cmd, ct);
            return result.IsSuccess
                ? Results.Created($"/v1/catalog/products/{result.Value}", new { id = result.Value })
                : Results.ValidationProblem(new Dictionary<string, string[]> {
                    [result.Error!.Value.Code] = new[] { result.Error.Value.Message }
                });
        }).WithTags("Catalog");

        group.MapGet("/products/{id:guid}", async (Guid id,  CancellationToken ct) =>
        {
            object? p = null;//await GetProduct.HandleAsync(new(id), db, ct);
            return p is null ? Results.NotFound() : Results.Ok(p);
        }).WithTags("Catalog");
    }
}

