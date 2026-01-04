# =============================================================================
# OpenMRS 3.x Frontend - Production Dockerfile
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Build Stage
# -----------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM node:22-alpine AS builder

# Build arguments - can be overridden at build time
ARG OMRS_API_URL=https://api.emr.hubuk.ng/openmrs
ARG OMRS_PUBLIC_PATH=/openmrs/spa
ARG OMRS_PAGE_TITLE=OpenMRS
ARG OMRS_OFFLINE=disable

# Set environment variables for webpack build
ENV OMRS_API_URL=https://api.emr.hubuk.ng/openmrs
ENV OMRS_PUBLIC_PATH=${OMRS_PUBLIC_PATH}
ENV OMRS_PAGE_TITLE=${OMRS_PAGE_TITLE}
ENV OMRS_OFFLINE=${OMRS_OFFLINE}
ENV NODE_ENV=production

WORKDIR /app

# Copy package files first for better caching
COPY package.json yarn.lock .yarnrc.yml ./
COPY .yarn ./.yarn
COPY packages ./packages
COPY turbo.json ./

# Install dependencies
RUN yarn install --immutable

# Build all packages
RUN yarn turbo run build

# Copy SPA assembly configuration
COPY spa-assemble-config.json ./

# Debug: Print environment variables to verify they're set
RUN echo "Building with OMRS_API_URL=${OMRS_API_URL}"
RUN echo "Building with OMRS_PUBLIC_PATH=${OMRS_PUBLIC_PATH}"

# Assemble the SPA
RUN node packages/tooling/openmrs/dist/cli.js assemble \
    --manifest \
    --mode config \
    --config spa-assemble-config.json \
    --target /app/spa

# Build the final application
RUN node packages/tooling/openmrs/dist/cli.js build \
    --target /app/spa

# Verify the build output
RUN ls -la /app/spa/

# -----------------------------------------------------------------------------
# Stage 2: Production Stage - serve
# -----------------------------------------------------------------------------
FROM node:22-alpine AS production

# Install serve globally
RUN npm install -g serve@14

# Create non-root user for security
RUN addgroup -g 1001 -S openmrs && \
    adduser -S -D -H -u 1001 -s /sbin/nologin -G openmrs openmrs

WORKDIR /app

# Create the directory structure
RUN mkdir -p /app/openmrs/spa

# Copy built application to the correct path
COPY --from=builder --chown=openmrs:openmrs /app/spa /app/openmrs/spa

# Copy serve configuration
COPY --chown=openmrs:openmrs serve.json ./

# Switch to non-root user
USER openmrs

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000/openmrs/spa/ || exit 1

CMD ["serve", "-c", "serve.json", "-l", "3000"]
