# --- Stage 1: Build the Go application ---
FROM golang:1.22-alpine AS builder

# Set the working directory inside the container
WORKDIR /app

# Copy dependency files first to utilize Docker layer caching
COPY go.mod ./
RUN go mod download

# Copy the remaining application source code
COPY . .

# Build a statically linked binary for Linux
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o webserver .

# --- Stage 2: Create the minimal runtime image ---
FROM alpine:3.19


# Set a non-root working directory
WORKDIR /root/

# Copy the pre-built binary from the builder stage
COPY --from=builder /app/webserver .

# Inform Docker that the container listens on port 8082
EXPOSE 8082

# Run the web server
CMD ["./webserver"]