FROM elixir:1.18-slim AS build
RUN apt-get update -qq && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
RUN mix local.hex --force && mix local.rebar --force
WORKDIR /app
COPY mix.exs mix.lock ./
RUN mix deps.get && mix deps.compile
COPY lib/ lib/
RUN MIX_ENV=prod mix compile

FROM elixir:1.18-slim
RUN apt-get update -qq && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
RUN mix local.hex --force && mix local.rebar --force
WORKDIR /app
COPY --from=build /app/ /app/
CMD ["mix", "run", "--no-halt"]
