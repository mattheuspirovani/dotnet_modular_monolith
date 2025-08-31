namespace BuildingBlocks.Domain;

public readonly record struct Error(string Code, string Message);


public readonly struct Result<T>
{
    private readonly T? _value;
    public bool IsSuccess { get; }
    public T Value => IsSuccess ? _value! : throw new InvalidOperationException("No value for failure result.");
    public Error? Error { get; }
    private Result(T value) { IsSuccess = true; _value = value; Error = null; }
    private Result(Error error) { IsSuccess = false; _value = default; Error = error; }
    public static Result<T> Success(T value) => new(value);
    public static Result<T> Failure(string code, string message) => new(new Error(code, message));
}