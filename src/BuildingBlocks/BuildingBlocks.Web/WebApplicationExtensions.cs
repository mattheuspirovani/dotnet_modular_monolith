using System.Reflection;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace BuildingBlocks.Web;

public static class WebApplicationExtensions
{
    public static IReadOnlyList<IModule> AddAndLoadModules(this IServiceCollection services, IConfiguration config, params Assembly[] assemblies)
    {
        var types = assemblies
            .SelectMany(a => a.GetTypes())
            .Where(t => !t.IsAbstract && !t.IsInterface && typeof(IModule).IsAssignableFrom(t))
            .ToList();


        var modules = new List<IModule>();
        foreach (var t in types)
        {
            if (Activator.CreateInstance(t) is IModule m)
            {
                m.AddModule(services, config);
                modules.Add(m);
            }
        }
        return modules;
    }


    public static void MapModuleEndpoints(this IEndpointRouteBuilder endpoints, IEnumerable<IModule> modules)
    {
        foreach (var m in modules)
            m.MapEndpoints(endpoints);
    }
}