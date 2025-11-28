# Build stage
FROM elixir:1.15.4 AS builder

# Install build dependencies
RUN apt-get update -y && \
    apt-get install -y \
    build-essential \
    git \
    curl \
    && apt-get clean && \
    rm -f /var/lib/apt/lists/*_*

# Install Node.js (LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set working directory
WORKDIR /app

# Set production environment
ENV MIX_ENV=prod

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && \
    mix deps.compile

# Copy configuration files
COPY config ./config

# Copy application code first (needed for phoenix-colocated generation)
COPY lib ./lib
COPY priv ./priv

# Compile application to generate phoenix-colocated files
RUN mix compile

# Install and build assets (after compilation so phoenix-colocated is available)
COPY assets ./assets
RUN cd assets && npm install && cd ..
RUN mix assets.setup && \
    mix assets.deploy

# Build release
RUN mix release

# Runtime stage - Use the same base as builder to avoid compatibility issues
FROM elixir:1.15.4 AS runtime

# Install minimal runtime dependencies
RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    postgresql-client \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Note: imagemagick is optional and can be added later if needed for image processing
# RUN apt-get update -y && apt-get install -y imagemagick && apt-get clean

# Set locale (Elixir image already has locale configured)
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Set working directory
WORKDIR /app

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/dobby ./

# Create uploads directory
RUN mkdir -p /app/priv/static/uploads

# Expose port
EXPOSE 4000

# Set environment
ENV PHX_SERVER=true
ENV MIX_ENV=prod

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:4000/ || exit 1

# Start the application
CMD ["./bin/dobby", "start"]

