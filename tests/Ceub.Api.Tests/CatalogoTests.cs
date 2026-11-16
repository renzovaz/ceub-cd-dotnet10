using Ceub.Api;
using Xunit;

namespace Ceub.Api.Tests;

public class CatalogoTests
{
    [Fact]
    public void Listar_DeveRetornarEntregasComIdentificadoresUnicos()
    {
        var entregas = Catalogo.Listar();
        Assert.NotEmpty(entregas);
        Assert.Equal(entregas.Length, entregas.Select(e => e.Id).Distinct().Count());
    }

    [Fact]
    public void Listar_DeveRetornarDescricoesEStatusPreenchidos()
    {
        Assert.All(Catalogo.Listar(), entrega => {
            Assert.False(string.IsNullOrWhiteSpace(entrega.Descricao));
            Assert.False(string.IsNullOrWhiteSpace(entrega.Status));
        });
    }
}
