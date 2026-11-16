using Ceub.Api;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();
var version = builder.Configuration["APP_VERSION"] ?? "local";
var commit = builder.Configuration["APP_COMMIT"] ?? "sem-commit";

app.MapGet("/", () => Results.Ok(new {
    aplicacao = "CEUB Delivery API", versao = version,
    commit, ambiente = app.Environment.EnvironmentName
}));

app.MapGet("/health", () =>
    builder.Configuration.GetValue<bool>("FAIL_HEALTH")
        ? Results.StatusCode(503)
        : Results.Ok(new { status = "ok", versao = version, commit }));

app.MapGet("/api/entregas", () => Results.Ok(Catalogo.Listar()));

app.MapGet("/api/novidade", () =>
    builder.Configuration.GetValue<bool>("FEATURE_NOVIDADE")
        ? Results.Ok(new { mensagem = "Nova consulta de entregas liberada!" })
        : Results.NotFound());

app.Run();
