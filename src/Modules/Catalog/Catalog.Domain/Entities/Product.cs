using BuildingBlocks.Domain;

namespace Catalog.Domain.Entities;

public sealed class Product : Entity<Guid>
{
    private Product() { }
    public string Name { get; private set; } = string.Empty;
    public decimal Price { get; private set; }


    public static Result<Product> Create(string name, decimal price)
    {
        if (string.IsNullOrWhiteSpace(name)) return Result<Product>.Failure("product.name.empty", "Name is required");
        if (price < 0) return Result<Product>.Failure("product.price.negative", "Price must be >= 0");
        var p = new Product { Id = Guid.NewGuid(), Name = name.Trim(), Price = price };
        return Result<Product>.Success(p);
    }


    public void Rename(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) throw new ArgumentException("Name required");
        Name = name.Trim();
    }
}