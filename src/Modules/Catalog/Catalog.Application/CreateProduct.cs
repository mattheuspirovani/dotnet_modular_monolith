using BuildingBlocks.Domain;
using Catalog.Domain;
using Catalog.Domain.Entities;
using FluentValidation;

namespace Catalog.Application;

public static class CreateProduct
{
    public sealed record Command(string Name, decimal Price);
    public sealed class Validator : AbstractValidator<Command>
    {
        public Validator()
        {
            RuleFor(x => x.Name).NotEmpty().MaximumLength(200);
            RuleFor(x => x.Price).GreaterThanOrEqualTo(0);
        }
    }


    public static async Task<Result<Guid>> HandleAsync(Command cmd, CancellationToken ct)
    {
        var validation = await new Validator().ValidateAsync(cmd, ct);
        if (!validation.IsValid)
        {
            var msg = string.Join("; ", validation.Errors.Select(e => e.ErrorMessage));
            return Result<Guid>.Failure("validation", msg);
        }


        var created = Product.Create(cmd.Name, cmd.Price);
        if (!created.IsSuccess) return Result<Guid>.Failure(created.Error!.Value.Code, created.Error.Value.Message);


        //await db.Products.AddAsync(created.Value, ct);
        //await db.SaveChangesAsync(ct);
        return Result<Guid>.Success(created.Value.Id);
    }
}


public static class GetProduct
{
    public sealed record Query(Guid Id);


    //public static async Task<Product?> HandleAsync(Query q, CancellationToken ct) => await db.Products.AsNoTracking().FirstOrDefaultAsync(p => p.Id == q.Id, ct);
}