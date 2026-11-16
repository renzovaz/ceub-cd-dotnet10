namespace Ceub.Api;

public record Entrega(int Id, string Descricao, string Status);

public static class Catalogo
{
    public static Entrega[] Listar() =>
    [
        new(1, "API publicada", "Concluida"),
        new(2, "Smoke test executado", "Concluida")
    ];
}
